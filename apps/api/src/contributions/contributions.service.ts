import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Db, isUniqueViolation, type Actor, type Queryable } from '../infra/database.js';
import { activeMembership, TODAY_DRC_SQL } from '../groups/membership.js';

type UserActor = Actor & { id: string };

export type PayMethod = 'mpesa' | 'airtel' | 'orange' | 'cash' | 'other';

export interface DeclareInput {
  method: PayMethod;
  txReference?: string;
  amountMinor: number;
  witnessMembershipId?: string;
  /** Identifiant généré par l'app : renvoyer la même déclaration (hors ligne, réseau coupé) ne crée pas de doublon. */
  offlineId: string;
}

export interface DecisionInput {
  decision: 'confirm' | 'witness' | 'dispute';
  note?: string;
}

/**
 * Référence de transaction normalisée : majuscules, sans espaces. Les formats exacts
 * des opérateurs (M-Pesa, Airtel Money, Orange Money) sont à confirmer avec de vrais
 * SMS : on ne vérifie ici qu'une forme plausible.
 */
export function normalizeTxReference(input: string): string | null {
  const ref = input.toUpperCase().replace(/\s/g, '');
  return /^[A-Z0-9][A-Z0-9.-]{4,29}$/.test(ref) ? ref : null;
}

interface ContributionRow {
  id: string;
  cycle_id: string;
  group_id: string;
  payer_membership_id: string;
  receiver_membership_id: string;
  witness_membership_id: string | null;
  amount_minor: string;
  method: PayMethod;
  tx_reference: string | null;
  status: 'declared' | 'confirmed' | 'disputed' | 'rejected';
  is_late: boolean;
  offline_id: string;
  declared_at: Date;
}

const CONTRIBUTION_COLUMNS = `id, cycle_id, group_id, payer_membership_id, receiver_membership_id,
  witness_membership_id, amount_minor, method, tx_reference, status, is_late, offline_id, declared_at`;

function toContribution(row: ContributionRow) {
  return {
    id: row.id,
    payerMembershipId: row.payer_membership_id,
    receiverMembershipId: row.receiver_membership_id,
    witnessMembershipId: row.witness_membership_id,
    amountMinor: Number(row.amount_minor),
    method: row.method,
    txReference: row.tx_reference,
    status: row.status,
    isLate: row.is_late,
    offlineId: row.offline_id,
    declaredAt: row.declared_at.toISOString(),
  };
}

@Injectable()
export class ContributionsService {
  constructor(private readonly db: Db) {}

  /** Tableau des tours : bénéficiaire, échéance, avancement des confirmations. */
  async board(userId: string, groupId: string) {
    const me = await this.requireMember(this.db, userId, groupId);
    const { rows } = await this.db.query<{
      cycle_number: number;
      due_date: string;
      status: string;
      beneficiary_membership_id: string;
      beneficiary_name: string;
      confirmed: number;
      expected: number;
    }>(
      `SELECT c.cycle_number, c.due_date::text AS due_date, c.status, c.beneficiary_membership_id,
              u.full_name AS beneficiary_name,
              (SELECT count(*)::int FROM contributions k
               WHERE k.cycle_id = c.id AND k.status = 'confirmed') AS confirmed,
              (SELECT count(*)::int - 1 FROM memberships x
               WHERE x.group_id = c.group_id AND x.status = 'active') AS expected
       FROM cycles c
       JOIN memberships m ON m.id = c.beneficiary_membership_id
       JOIN users u ON u.id = m.user_id
       WHERE c.group_id = $1
       ORDER BY c.cycle_number`,
      [groupId],
    );
    return {
      myMembershipId: me.id,
      cycles: rows.map((r) => ({
        cycleNumber: r.cycle_number,
        dueDate: r.due_date,
        status: r.status,
        beneficiary: { membershipId: r.beneficiary_membership_id, fullName: r.beneficiary_name },
        confirmedCount: r.confirmed,
        expectedCount: r.expected,
      })),
    };
  }

  /** Détail d'un tour : pour chaque membre qui doit payer, où en est sa cotisation. */
  async cycle(userId: string, groupId: string, cycleNumber: number) {
    const me = await this.requireMember(this.db, userId, groupId);
    const cycle = await this.findCycle(this.db, groupId, cycleNumber);
    const { rows } = await this.db.query<
      Partial<ContributionRow> & {
        membership_id: string;
        full_name: string;
        turn_order: number | null;
        overdue: boolean;
        decisions: { decision: string; membershipId: string; at: string }[] | null;
      }
    >(
      `SELECT m.id AS membership_id, u.full_name, m.turn_order,
              ($2::date < ${TODAY_DRC_SQL}) AS overdue,
              k.id, k.witness_membership_id, k.amount_minor, k.method, k.tx_reference, k.status,
              k.is_late, k.offline_id, k.declared_at, k.payer_membership_id, k.receiver_membership_id,
              (SELECT json_agg(json_build_object('decision', f.decision,
                                                 'membershipId', f.confirmed_by,
                                                 'at', f.confirmed_at) ORDER BY f.confirmed_at)
               FROM confirmations f WHERE f.contribution_id = k.id) AS decisions
       FROM memberships m
       JOIN users u ON u.id = m.user_id
       LEFT JOIN LATERAL (
         SELECT * FROM contributions x
         WHERE x.cycle_id = $3 AND x.payer_membership_id = m.id AND x.status <> 'rejected'
         ORDER BY x.declared_at DESC LIMIT 1
       ) k ON true
       WHERE m.group_id = $1 AND m.status = 'active' AND m.id <> $4
       ORDER BY m.turn_order NULLS LAST, u.full_name`,
      [groupId, cycle.due_date, cycle.id, cycle.beneficiary_membership_id],
    );
    return {
      myMembershipId: me.id,
      cycleNumber,
      dueDate: cycle.due_date,
      status: cycle.status,
      beneficiaryMembershipId: cycle.beneficiary_membership_id,
      payers: rows.map((r) => ({
        membershipId: r.membership_id,
        fullName: r.full_name,
        // Pas de déclaration : « attendue », ou « en retard » après l'échéance
        status: r.status ?? (r.overdue ? 'late' : 'expected'),
        contribution: r.id ? toContribution(r as ContributionRow) : null,
        decisions: r.decisions ?? [],
      })),
    };
  }

  /** Le payeur déclare avoir payé le bénéficiaire du tour. */
  async declare(actor: UserActor, groupId: string, cycleNumber: number, input: DeclareInput) {
    const result = await this.db
      .transaction(actor, async (q) => {
        const payer = await this.requireMember(q, actor.id, groupId);
        const group = await q.query<{ status: string; amount: string; currency: string }>(
          `SELECT status, contribution_amount_minor AS amount, currency FROM groups WHERE id = $1`,
          [groupId],
        );
        if (group.rows[0].status !== 'active') {
          throw new ConflictException(
            group.rows[0].status === 'draft'
              ? "Le groupe n'a pas encore démarré."
              : 'Le groupe est terminé.',
          );
        }
        const cycle = await this.findCycle(q, groupId, cycleNumber);
        if (cycle.status === 'completed' || cycle.status === 'cancelled') {
          throw new ConflictException('Ce tour est clos.');
        }

        // Renvoi de la même déclaration (réseau coupé, nouvel essai) : on rend l'existante
        const existing = await q.query<ContributionRow>(
          `SELECT ${CONTRIBUTION_COLUMNS} FROM contributions WHERE offline_id = $1`,
          [input.offlineId],
        );
        if (existing.rows[0]) {
          if (existing.rows[0].payer_membership_id !== payer.id) {
            throw new ConflictException('Identifiant de déclaration déjà utilisé.');
          }
          return { contribution: existing.rows[0], replayed: true };
        }

        if (payer.id === cycle.beneficiary_membership_id) {
          throw new BadRequestException('Vous êtes le bénéficiaire de ce tour : vous ne cotisez pas pour vous-même.');
        }
        if (input.amountMinor !== Number(group.rows[0].amount)) {
          throw new BadRequestException(
            `Le montant doit être celui du groupe : ${group.rows[0].amount} (${group.rows[0].currency}, unités mineures).`,
          );
        }

        let txReference: string | null = null;
        let witness: string | null = null;
        if (input.method === 'cash') {
          if (!input.witnessMembershipId) {
            throw new BadRequestException('Pour un paiement en espèces, désignez un témoin du groupe.');
          }
          witness = input.witnessMembershipId.toLowerCase();
          const ok = await q.query(
            `SELECT 1 FROM memberships WHERE id = $1 AND group_id = $2 AND status = 'active'`,
            [witness, groupId],
          );
          if (ok.rowCount !== 1 || witness === payer.id || witness === cycle.beneficiary_membership_id) {
            throw new BadRequestException(
              'Le témoin doit être un autre membre du groupe, ni vous ni le bénéficiaire.',
            );
          }
        } else {
          if (input.witnessMembershipId) {
            throw new BadRequestException('Le témoin ne concerne que les paiements en espèces.');
          }
          txReference = normalizeTxReference(input.txReference ?? '');
          if (!txReference) {
            throw new BadRequestException(
              "L'ID de transaction est obligatoire pour un paiement mobile money (5 à 30 lettres ou chiffres).",
            );
          }
        }

        const inserted = await q.query<ContributionRow>(
          `INSERT INTO contributions (cycle_id, group_id, payer_membership_id, receiver_membership_id,
                                      witness_membership_id, amount_minor, method, tx_reference,
                                      is_late, offline_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::date < ${TODAY_DRC_SQL}, $10)
           RETURNING ${CONTRIBUTION_COLUMNS}`,
          [
            cycle.id,
            groupId,
            payer.id,
            cycle.beneficiary_membership_id,
            witness,
            input.amountMinor,
            input.method,
            txReference,
            cycle.due_date,
            input.offlineId,
          ],
        );
        return { contribution: inserted.rows[0], replayed: false };
      })
      .catch((e: unknown) => {
        if (isUniqueViolation(e, 'uq_contrib_txref')) {
          throw new ConflictException('Cet ID de transaction a déjà été utilisé pour une autre cotisation.');
        }
        if (isUniqueViolation(e, 'uq_contrib_active_per_payer')) {
          throw new ConflictException('Vous avez déjà déclaré une cotisation pour ce tour.');
        }
        throw e;
      });
    return { ...toContribution(result.contribution), replayed: result.replayed };
  }

  /**
   * Réponse à une déclaration :
   *   confirm : le bénéficiaire a bien reçu ;
   *   witness : le témoin a vu la remise en espèces ;
   *   dispute : contestation (motif obligatoire), par tout membre autre que le payeur.
   * La base vérifie elle-même qui a le droit de répondre (db/003_cash_witness.sql).
   */
  async decide(actor: UserActor, contributionId: string, input: DecisionInput) {
    return this.db.transaction(actor, async (q) => {
      const found = await q.query<ContributionRow>(
        `SELECT ${CONTRIBUTION_COLUMNS} FROM contributions WHERE id = $1 FOR UPDATE`,
        [contributionId],
      );
      const c = found.rows[0];
      const me = c ? await activeMembership(q, actor.id, c.group_id) : null;
      if (!c || !me) throw new NotFoundException('Cotisation introuvable.');

      if (input.decision === 'dispute') {
        if (me.id === c.payer_membership_id) {
          throw new ForbiddenException('Le payeur ne conteste pas sa propre cotisation.');
        }
        if (!input.note?.trim()) throw new BadRequestException('Expliquez la contestation.');
        if (c.status !== 'declared') {
          throw new ConflictException(`Cette cotisation ne peut plus être contestée (statut : ${c.status}).`);
        }
      } else {
        if (c.status !== 'declared' && c.status !== 'disputed') {
          throw new ConflictException(`Cette cotisation est déjà ${c.status === 'confirmed' ? 'confirmée' : 'rejetée'}.`);
        }
        if (input.decision === 'confirm' && me.id !== c.receiver_membership_id) {
          throw new ForbiddenException('Seul le bénéficiaire du tour confirme avoir reçu le paiement.');
        }
        if (input.decision === 'witness' && me.id !== c.witness_membership_id) {
          throw new ForbiddenException('Seul le témoin désigné confirme la remise en espèces.');
        }
      }

      await q
        .query(
          `INSERT INTO confirmations (contribution_id, confirmed_by, decision, note)
           VALUES ($1, $2, $3, $4)`,
          [c.id, me.id, input.decision, input.note?.trim() || null],
        )
        .catch((e: unknown) => {
          if (isUniqueViolation(e, 'uq_confirmations_once')) {
            throw new ConflictException('Vous avez déjà donné cette réponse.');
          }
          throw e;
        });

      let status: ContributionRow['status'] = c.status;
      if (input.decision === 'dispute') {
        await q.query(
          `INSERT INTO disputes (contribution_id, opened_by, reason) VALUES ($1, $2, $3)`,
          [c.id, me.id, input.note!.trim()],
        );
        status = 'disputed';
      } else if (await this.hasRequiredConfirmations(q, c)) {
        status = 'confirmed';
        // Une confirmation du bénéficiaire après contestation clôt la contestation
        await q.query(
          `UPDATE disputes SET status = 'resolved_confirmed', resolved_at = now()
           WHERE contribution_id = $1 AND status = 'open'`,
          [c.id],
        );
      }
      if (status !== c.status) {
        // Le numéro de reçu naît avec la confirmation, dans la même écriture (donc journalisé)
        await q.query(
          `UPDATE contributions SET status = $2::contribution_status,
             receipt_number = CASE WHEN $2 = 'confirmed' THEN nextval('receipt_number_seq') END
           WHERE id = $1`,
          [c.id, status],
        );
      }
      const cycleStatus = status === 'confirmed' ? await this.closeCycleIfComplete(q, c.cycle_id) : null;
      return { ...toContribution({ ...c, status }), cycleStatus };
    });
  }

  private async hasRequiredConfirmations(q: Queryable, c: ContributionRow): Promise<boolean> {
    const { rows } = await q.query<{ receiver: boolean; witness: boolean }>(
      `SELECT bool_or(decision = 'confirm' AND confirmed_by = $2) AS receiver,
              bool_or(decision = 'witness' AND confirmed_by = $3) AS witness
       FROM confirmations WHERE contribution_id = $1`,
      [c.id, c.receiver_membership_id, c.witness_membership_id],
    );
    return Boolean(rows[0].receiver) && (c.method !== 'cash' || Boolean(rows[0].witness));
  }

  /** Tous les membres ont payé : le tour est clos, le suivant s'ouvre ; après le dernier, le groupe est terminé. */
  private async closeCycleIfComplete(q: Queryable, cycleId: string): Promise<string> {
    const { rows } = await q.query<{ group_id: string; cycle_number: number; done: boolean }>(
      `SELECT c.group_id, c.cycle_number,
              (SELECT count(*) FROM contributions k WHERE k.cycle_id = c.id AND k.status = 'confirmed')
                >= (SELECT count(*) - 1 FROM memberships m
                    WHERE m.group_id = c.group_id AND m.status = 'active') AS done
       FROM cycles c WHERE c.id = $1 FOR UPDATE`,
      [cycleId],
    );
    const cycle = rows[0];
    if (!cycle.done) return 'open';
    await q.query(`UPDATE cycles SET status = 'completed' WHERE id = $1`, [cycleId]);
    const next = await q.query(
      `UPDATE cycles SET status = 'open'
       WHERE group_id = $1 AND cycle_number = $2 AND status = 'upcoming'`,
      [cycle.group_id, cycle.cycle_number + 1],
    );
    if (next.rowCount === 0) {
      const remaining = await q.query(
        `SELECT 1 FROM cycles WHERE group_id = $1 AND status NOT IN ('completed', 'cancelled')`,
        [cycle.group_id],
      );
      if (remaining.rowCount === 0) {
        await q.query(`UPDATE groups SET status = 'closed' WHERE id = $1`, [cycle.group_id]);
      }
    }
    return 'completed';
  }

  /**
   * Reçu d'une cotisation confirmée. Il renvoie à l'événement du journal qui l'a confirmée
   * (seq + hash) : le QR code permet de retrouver et de vérifier cet événement.
   */
  async receipt(userId: string, contributionId: string) {
    const found = await this.db.query<{
      id: string;
      group_id: string;
      status: string;
      receipt_number: string | null;
      group_name: string;
      currency: string;
      amount_minor: string;
      method: PayMethod;
      tx_reference: string | null;
      is_late: boolean;
      declared_at: Date;
      cycle_number: number;
      due_date: string;
      payer_name: string;
      payer_phone: string;
      beneficiary_name: string;
      beneficiary_phone: string;
      witness_name: string | null;
      confirmed_at: Date | null;
    }>(
      `SELECT k.id, k.group_id, k.status, k.receipt_number, g.name AS group_name, g.currency,
              k.amount_minor, k.method, k.tx_reference, k.is_late, k.declared_at,
              c.cycle_number, c.due_date::text AS due_date,
              pu.full_name AS payer_name, pu.phone AS payer_phone,
              ru.full_name AS beneficiary_name, ru.phone AS beneficiary_phone,
              wu.full_name AS witness_name,
              (SELECT max(f.confirmed_at) FROM confirmations f
               WHERE f.contribution_id = k.id AND f.decision IN ('confirm', 'witness')) AS confirmed_at
       FROM contributions k
       JOIN groups g ON g.id = k.group_id
       JOIN cycles c ON c.id = k.cycle_id
       JOIN memberships pm ON pm.id = k.payer_membership_id JOIN users pu ON pu.id = pm.user_id
       JOIN memberships rm ON rm.id = k.receiver_membership_id JOIN users ru ON ru.id = rm.user_id
       LEFT JOIN memberships wm ON wm.id = k.witness_membership_id
       LEFT JOIN users wu ON wu.id = wm.user_id
       WHERE k.id = $1`,
      [contributionId],
    );
    const r = found.rows[0];
    if (!r || !(await activeMembership(this.db, userId, r.group_id))) {
      throw new NotFoundException('Cotisation introuvable.');
    }
    if (r.status !== 'confirmed' || !r.receipt_number) {
      throw new ConflictException("Pas encore de reçu : la cotisation n'est pas confirmée.");
    }

    const chainId = `group:${r.group_id}`;
    const event = await this.db.query<{ seq: string; hash: string }>(
      `SELECT seq, hash FROM audit_log
       WHERE chain_id = $1 AND action = 'contributions.update'
         AND payload::jsonb ->> 'id' = $2 AND payload::jsonb ->> 'status' = 'confirmed'
       ORDER BY seq LIMIT 1`,
      [chainId, r.id],
    );
    const receiptNumber = `MCH-${r.receipt_number.padStart(8, '0')}`;
    const audit = { chainId, seq: Number(event.rows[0].seq), hash: event.rows[0].hash };
    return {
      receiptNumber,
      contributionId: r.id,
      groupId: r.group_id,
      groupName: r.group_name,
      cycleNumber: r.cycle_number,
      dueDate: r.due_date,
      currency: r.currency,
      amountMinor: Number(r.amount_minor),
      method: r.method,
      txReference: r.tx_reference,
      isLate: r.is_late,
      payer: { fullName: r.payer_name, phone: r.payer_phone },
      beneficiary: { fullName: r.beneficiary_name, phone: r.beneficiary_phone },
      witness: r.witness_name ? { fullName: r.witness_name } : null,
      declaredAt: r.declared_at.toISOString(),
      confirmedAt: r.confirmed_at!.toISOString(),
      audit,
      // Contenu du QR code (format documenté dans spec/receipts.md)
      qrPayload: `MCHANGO1|${receiptNumber}|${r.id}|${r.group_id}|${audit.seq}|${audit.hash}`,
    };
  }

  /**
   * Carnet personnel, toutes tontines confondues : ce que j'ai versé et reçu (paiements confirmés),
   * mes prochains paiements et mon tour. Des montants constatés, pas un solde : Mchango ne détient rien.
   */
  async carnet(userId: string) {
    const groups = await this.db.query<{
      group_id: string;
      name: string;
      status: string;
      currency: string;
      amount: string;
      frequency: string;
      membership_id: string;
      my_cycle: number | null;
      my_due: string | null;
      my_cycle_status: string | null;
      expected: number;
      paid_count: number;
      paid: string;
      received: string;
      received_count: number;
      pending: number;
    }>(
      `SELECT g.id AS group_id, g.name, g.status, g.currency, g.contribution_amount_minor AS amount, g.frequency,
              m.id AS membership_id,
              mc.cycle_number AS my_cycle, mc.due_date::text AS my_due, mc.status AS my_cycle_status,
              (SELECT count(*)::int - 1 FROM memberships x WHERE x.group_id = g.id AND x.status = 'active') AS expected,
              (SELECT count(*)::int FROM contributions k WHERE k.payer_membership_id = m.id AND k.status = 'confirmed') AS paid_count,
              (SELECT coalesce(sum(k.amount_minor), 0) FROM contributions k
                WHERE k.payer_membership_id = m.id AND k.status = 'confirmed') AS paid,
              (SELECT coalesce(sum(k.amount_minor), 0) FROM contributions k
                WHERE k.receiver_membership_id = m.id AND k.status = 'confirmed') AS received,
              (SELECT count(*)::int FROM contributions k
                WHERE k.receiver_membership_id = m.id AND k.status = 'confirmed') AS received_count,
              (SELECT count(*)::int FROM contributions k
                WHERE k.payer_membership_id = m.id AND k.status IN ('declared', 'disputed')) AS pending
       FROM memberships m
       JOIN groups g ON g.id = m.group_id
       LEFT JOIN cycles mc ON mc.group_id = g.id AND mc.beneficiary_membership_id = m.id
       WHERE m.user_id = $1 AND m.status = 'active'
       ORDER BY g.created_at DESC`,
      [userId],
    );
    // Prochain paiement à faire dans chaque tontine en cours : le premier tour non payé dont je ne suis pas bénéficiaire
    const toPay = await this.db.query<{
      group_id: string;
      name: string;
      currency: string;
      amount: string;
      cycle_number: number;
      due_date: string;
      beneficiary: string;
      late: boolean;
    }>(
      `SELECT DISTINCT ON (g.id) g.id AS group_id, g.name, g.currency, g.contribution_amount_minor AS amount,
              c.cycle_number, c.due_date::text AS due_date, bu.full_name AS beneficiary,
              c.due_date < ${TODAY_DRC_SQL} AS late
       FROM memberships m
       JOIN groups g ON g.id = m.group_id AND g.status = 'active'
       JOIN cycles c ON c.group_id = g.id AND c.status IN ('open', 'upcoming') AND c.beneficiary_membership_id <> m.id
       JOIN memberships bm ON bm.id = c.beneficiary_membership_id JOIN users bu ON bu.id = bm.user_id
       WHERE m.user_id = $1 AND m.status = 'active'
         AND NOT EXISTS (SELECT 1 FROM contributions k
                         WHERE k.cycle_id = c.id AND k.payer_membership_id = m.id AND k.status <> 'rejected')
       ORDER BY g.id, c.cycle_number`,
      [userId],
    );

    const totals = new Map<string, { currency: string; paidMinor: number; receivedMinor: number }>();
    for (const g of groups.rows) {
      const t = totals.get(g.currency) ?? { currency: g.currency, paidMinor: 0, receivedMinor: 0 };
      t.paidMinor += Number(g.paid);
      t.receivedMinor += Number(g.received);
      totals.set(g.currency, t);
    }
    const upcoming = [
      ...toPay.rows.map((p) => ({
        kind: 'pay' as const,
        groupId: p.group_id,
        groupName: p.name,
        cycleNumber: p.cycle_number,
        dueDate: p.due_date,
        amountMinor: Number(p.amount),
        currency: p.currency,
        counterpart: p.beneficiary,
        late: p.late,
      })),
      ...groups.rows
        .filter((g) => g.status === 'active' && g.my_cycle !== null && g.my_cycle_status !== 'completed' && g.my_cycle_status !== 'cancelled')
        .map((g) => ({
          kind: 'receive' as const,
          groupId: g.group_id,
          groupName: g.name,
          cycleNumber: g.my_cycle!,
          dueDate: g.my_due!,
          amountMinor: Number(g.amount) * g.expected,
          currency: g.currency,
          counterpart: null,
          late: false,
        })),
    ].sort((a, b) => a.dueDate.localeCompare(b.dueDate) || (a.kind === 'pay' ? -1 : 1));

    return {
      totals: [...totals.values()],
      upcoming,
      groups: groups.rows.map((g) => ({
        groupId: g.group_id,
        name: g.name,
        status: g.status,
        currency: g.currency,
        contributionAmountMinor: Number(g.amount),
        frequency: g.frequency,
        myTurn: g.my_cycle === null ? null : { cycleNumber: g.my_cycle, dueDate: g.my_due, status: g.my_cycle_status },
        paidCount: g.paid_count,
        paidMinor: Number(g.paid),
        receivedCount: g.received_count,
        receivedMinor: Number(g.received),
        pendingCount: g.pending,
      })),
    };
  }

  private async requireMember(q: Queryable, userId: string, groupId: string) {
    const me = await activeMembership(q, userId, groupId);
    if (!me) throw new NotFoundException('Groupe introuvable.');
    return me;
  }

  private async findCycle(q: Queryable, groupId: string, cycleNumber: number) {
    const { rows } = await q.query<{
      id: string;
      due_date: string;
      status: string;
      beneficiary_membership_id: string;
    }>(
      `SELECT id, due_date::text AS due_date, status, beneficiary_membership_id
       FROM cycles WHERE group_id = $1 AND cycle_number = $2`,
      [groupId, cycleNumber],
    );
    if (!rows[0]) throw new NotFoundException('Tour introuvable.');
    return rows[0];
  }
}
