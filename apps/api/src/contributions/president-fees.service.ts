import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Db, isUniqueViolation, type Actor, type Queryable } from '../infra/database.js';
import { activeMembership } from '../groups/membership.js';
import type { PayMethod } from './contributions.service.js';
import { normalizeTxReference } from './tx-reference.js';

type UserActor = Actor & { id: string };

interface FeeRow {
  id: string;
  status: 'declared' | 'confirmed' | 'disputed' | 'rejected';
  amount_minor: string;
  method: PayMethod;
  tx_reference: string | null;
  note: string | null;
  declared_at: Date;
  decided_at: Date | null;
  payer_membership_id: string;
  receiver_membership_id: string;
  group_id: string;
}

const FEE_COLUMNS = `id, status, amount_minor, method, tx_reference, note, declared_at, decided_at,
  payer_membership_id, receiver_membership_id, group_id`;

function toFee(r: FeeRow) {
  return {
    id: r.id,
    status: r.status,
    amountMinor: Number(r.amount_minor),
    method: r.method,
    txReference: r.tx_reference,
    note: r.note,
    declaredAt: r.declared_at.toISOString(),
    decidedAt: r.decided_at?.toISOString() ?? null,
  };
}

/** Ce qu'il faut savoir de la part du président pour un tour. */
export interface CycleFee {
  /** Points de base du règlement (500 = 5 %). */
  bps: number;
  amountMinor: number;
  payerMembershipId: string;
  presidentMembershipId: string;
  payment: ReturnType<typeof toFee> | null;
}

/**
 * Part du président (spec/president-fee.md) : de 0 à 10 % de la mise de chaque tour, acceptée par
 * tous en signant le règlement. Le bénéficiaire du tour la paie au président (hors de Mchango), le
 * déclare ; le président confirme. Au tour du président, il n'y a rien à payer.
 */
@Injectable()
export class PresidentFeesService {
  constructor(private readonly db: Db) {}

  /** La part de ce tour, ou null s'il n'y en a pas (0 %, ou tour du président lui-même). */
  async forCycle(q: Queryable, groupId: string, cycleId: string, beneficiaryId: string): Promise<CycleFee | null> {
    const { rows } = await q.query<{ bps: number; amount: string; members: number; president: string | null }>(
      `SELECT g.president_fee_bps AS bps, g.contribution_amount_minor AS amount,
              (SELECT count(*)::int FROM memberships m WHERE m.group_id = g.id AND m.status = 'active') AS members,
              (SELECT m.id FROM memberships m WHERE m.group_id = g.id AND m.role = 'president' AND m.status = 'active'
               LIMIT 1) AS president
       FROM groups g WHERE g.id = $1`,
      [groupId],
    );
    const g = rows[0];
    if (!g || g.bps === 0 || !g.president || g.president === beneficiaryId) return null;
    // Même calcul que la base (trigger president_fees_check_parties) : arrondi vers le bas
    const amountMinor = Math.floor((Number(g.amount) * (g.members - 1) * g.bps) / 10000);
    if (amountMinor <= 0) return null;
    const paid = await q.query<FeeRow>(
      `SELECT ${FEE_COLUMNS} FROM president_fees WHERE cycle_id = $1 AND status <> 'rejected'
       ORDER BY declared_at DESC LIMIT 1`,
      [cycleId],
    );
    return {
      bps: g.bps,
      amountMinor,
      payerMembershipId: beneficiaryId,
      presidentMembershipId: g.president,
      payment: paid.rows[0] ? toFee(paid.rows[0]) : null,
    };
  }

  /** Le bénéficiaire déclare avoir payé la part du président de son tour. */
  async declare(
    actor: UserActor,
    groupId: string,
    cycleNumber: number,
    input: { method: PayMethod; txReference?: string; offlineId: string },
  ) {
    return this.db
      .transaction(actor, async (q) => {
        const me = await activeMembership(q, actor.id, groupId);
        if (!me) throw new NotFoundException('Groupe introuvable.');
        const cycle = await q.query<{ id: string; beneficiary_membership_id: string; status: string }>(
          `SELECT c.id, c.beneficiary_membership_id, c.status FROM cycles c
           JOIN groups g ON g.id = c.group_id WHERE c.group_id = $1 AND c.cycle_number = $2 AND g.status = 'active'`,
          [groupId, cycleNumber],
        );
        const c = cycle.rows[0];
        if (!c) throw new NotFoundException('Tour introuvable.');
        if (c.beneficiary_membership_id !== me.id) {
          throw new ForbiddenException('Seul le bénéficiaire du tour paie la part du président.');
        }
        const replay = await q.query<FeeRow>(`SELECT ${FEE_COLUMNS} FROM president_fees WHERE offline_id = $1`, [input.offlineId]);
        if (replay.rows[0]) return toFee(replay.rows[0]);

        const fee = await this.forCycle(q, groupId, c.id, c.beneficiary_membership_id);
        if (!fee) throw new ConflictException("Ce tour n'a pas de part du président à payer.");
        let tx: string | null = null;
        if (input.method !== 'cash') {
          tx = normalizeTxReference(input.txReference ?? '');
          if (!tx) {
            throw new BadRequestException(
              "L'ID de transaction est obligatoire pour un paiement mobile money (5 à 30 lettres ou chiffres).",
            );
          }
        }
        const { rows } = await q.query<FeeRow>(
          `INSERT INTO president_fees (group_id, cycle_id, payer_membership_id, receiver_membership_id, amount_minor,
                                       method, tx_reference, offline_id)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
           RETURNING ${FEE_COLUMNS}`,
          [groupId, c.id, me.id, fee.presidentMembershipId, fee.amountMinor, input.method, tx, input.offlineId],
        );
        return toFee(rows[0]);
      })
      .catch((e: unknown) => {
        if (isUniqueViolation(e, 'uq_president_fee_active')) {
          throw new ConflictException('La part du président de ce tour est déjà déclarée.');
        }
        if (isUniqueViolation(e, 'uq_president_fee_txref')) {
          throw new ConflictException('Cet ID de transaction a déjà été utilisé pour une autre cotisation.');
        }
        throw e;
      });
  }

  /** Le président confirme l'avoir reçue, ou signale un problème (motif obligatoire). */
  async decide(actor: UserActor, feeId: string, input: { decision: 'confirm' | 'dispute'; note?: string }) {
    return this.db.transaction(actor, async (q) => {
      const found = await q.query<FeeRow>(`SELECT ${FEE_COLUMNS} FROM president_fees WHERE id = $1 FOR UPDATE`, [feeId]);
      const f = found.rows[0];
      const me = f ? await activeMembership(q, actor.id, f.group_id) : null;
      if (!f || !me) throw new NotFoundException('Paiement introuvable.');
      if (me.id !== f.receiver_membership_id) {
        throw new ForbiddenException('Seul le président confirme avoir reçu sa part.');
      }
      if (f.status === 'confirmed' || f.status === 'rejected') {
        throw new ConflictException('Ce paiement a déjà reçu une réponse.');
      }
      if (input.decision === 'dispute' && !input.note?.trim()) throw new BadRequestException('Expliquez la contestation.');
      const status = input.decision === 'confirm' ? 'confirmed' : 'disputed';
      const { rows } = await q.query<FeeRow>(
        `UPDATE president_fees SET status = $2::president_fee_status, note = coalesce($3, note), decided_at = now()
         WHERE id = $1 RETURNING ${FEE_COLUMNS}`,
        [f.id, status, input.note?.trim() || null],
      );
      return toFee(rows[0]);
    });
  }
}
