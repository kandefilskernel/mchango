import { Inject, Injectable, Logger } from '@nestjs/common';
import { Db } from '../infra/database.js';
import { SMS_SENDER, type SmsSender } from '../infra/sms.js';
import { toGsm7 } from '../infra/sms-text.js';

/** Plage d'envoi, heure de Lubumbashi : pas de SMS la nuit. */
export const SEND_FROM_HOUR = 8;
export const SEND_UNTIL_HOUR = 20;

const TZ = 'Africa/Lubumbashi';

/** Montant en unités mineures, pour un SMS : « 20 000 FC », « 20,50 $ ». */
export function smsAmount(minor: number, currency: string): string {
  const group = (n: number) => n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return currency === 'USD'
    ? `${group(Math.floor(minor / 100))},${(minor % 100).toString().padStart(2, '0')} $`
    : `${group(minor)} FC`;
}

const clip = (s: string, max: number) => (s.length <= max ? s : `${s.slice(0, max - 1)}.`);

/**
 * Texte du rappel. Noms tronqués et caractères ramenés à l'alphabet GSM-7 : un seul SMS
 * (160 caractères), quel que soit le nom du groupe ou du bénéficiaire.
 */
export function reminderMessage(r: {
  groupName: string;
  cycleNumber: number;
  amountMinor: number;
  currency: string;
  beneficiaryName: string;
  beneficiaryPhone: string;
  dueDate: string;
  dueToday: boolean;
}): string {
  const [y, m, d] = r.dueDate.split('-');
  const when = r.dueToday ? "aujourd'hui" : `d'ici le ${d}/${m}/${y}`;
  return toGsm7(
    `Mchango : ${clip(r.groupName, 20)}, tour ${r.cycleNumber}. Payez ${smsAmount(r.amountMinor, r.currency)} ` +
      `à ${clip(r.beneficiaryName, 18)} (${r.beneficiaryPhone}) ${when}, puis déclarez-le dans l'app.`,
  );
}

function localParts(now: Date) {
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: TZ }).format(now);
  const hour = Number(new Intl.DateTimeFormat('en-GB', { timeZone: TZ, hour: '2-digit', hourCycle: 'h23' }).format(now));
  return { date, hour };
}

export interface ReminderRun {
  sent: number;
  failed: number;
}

/**
 * Un rappel par membre et par tour, aux membres qui n'ont pas encore déclaré leur paiement :
 * la veille de l'échéance (tontines hebdomadaires et mensuelles) ou le matin même (quotidiennes).
 * Le bénéficiaire du tour ne reçoit rien : il ne paie pas.
 */
@Injectable()
export class RemindersService {
  private readonly logger = new Logger('Rappels');

  constructor(
    private readonly db: Db,
    @Inject(SMS_SENDER) private readonly sms: SmsSender,
  ) {}

  async runOnce(now: Date = new Date()): Promise<ReminderRun> {
    const { date: today, hour } = localParts(now);
    if (hour < SEND_FROM_HOUR || hour >= SEND_UNTIL_HOUR) return { sent: 0, failed: 0 };

    const due = await this.db.query<{
      cycle_id: string;
      cycle_number: number;
      due_date: string;
      due_today: boolean;
      group_name: string;
      currency: string;
      amount: string;
      membership_id: string;
      user_id: string;
      phone: string;
      beneficiary_name: string;
      beneficiary_phone: string;
    }>(
      `SELECT c.id AS cycle_id, c.cycle_number, c.due_date::text AS due_date, c.due_date = $1::date AS due_today,
              g.name AS group_name, g.currency, g.contribution_amount_minor AS amount,
              m.id AS membership_id, u.id AS user_id, u.phone,
              bu.full_name AS beneficiary_name, bu.phone AS beneficiary_phone
       FROM cycles c
       JOIN groups g ON g.id = c.group_id
       JOIN memberships bm ON bm.id = c.beneficiary_membership_id
       JOIN users bu ON bu.id = bm.user_id
       JOIN memberships m ON m.group_id = c.group_id AND m.status = 'active'
                         AND m.id <> c.beneficiary_membership_id
       JOIN users u ON u.id = m.user_id AND NOT u.is_blocked
       WHERE g.status = 'active'
         AND c.status IN ('open', 'upcoming')
         AND c.due_date = CASE g.frequency WHEN 'daily' THEN $1::date ELSE $1::date + 1 END
         AND NOT EXISTS (SELECT 1 FROM contributions k
                         WHERE k.cycle_id = c.id AND k.payer_membership_id = m.id AND k.status <> 'rejected')
         AND NOT EXISTS (SELECT 1 FROM notifications n
                         WHERE n.dedupe_key = 'reminder:' || c.id || ':' || m.id)`,
      [today],
    );

    const run: ReminderRun = { sent: 0, failed: 0 };
    for (const r of due.rows) {
      const message = reminderMessage({
        groupName: r.group_name,
        cycleNumber: r.cycle_number,
        amountMinor: Number(r.amount),
        currency: r.currency,
        beneficiaryName: r.beneficiary_name,
        beneficiaryPhone: r.beneficiary_phone,
        dueDate: r.due_date,
        dueToday: r.due_today,
      });
      // Réserver avant d'envoyer : si un autre serveur a déjà pris ce rappel, on ne l'envoie pas
      const claimed = await this.db.query<{ id: string }>(
        `INSERT INTO notifications (user_id, channel, template, payload, dedupe_key)
         VALUES ($1, 'sms', 'contribution_reminder', $2, $3)
         ON CONFLICT (dedupe_key) DO NOTHING RETURNING id`,
        [
          r.user_id,
          JSON.stringify({ cycle_id: r.cycle_id, membership_id: r.membership_id, message }),
          `reminder:${r.cycle_id}:${r.membership_id}`,
        ],
      );
      if (claimed.rowCount !== 1) continue;

      try {
        await this.sms.send(r.phone, message);
        await this.db.query(`UPDATE notifications SET status = 'sent', sent_at = now() WHERE id = $1`, [
          claimed.rows[0].id,
        ]);
        run.sent++;
      } catch (e) {
        // Pas de nouvel essai automatique au MVP : l'échec reste visible dans notifications
        await this.db.query(`UPDATE notifications SET status = 'failed', error = $2 WHERE id = $1`, [
          claimed.rows[0].id,
          String(e).slice(0, 500),
        ]);
        run.failed++;
      }
    }
    if (run.sent || run.failed) this.logger.log(`${run.sent} rappel(s) envoyé(s), ${run.failed} échec(s)`);
    return run;
  }
}
