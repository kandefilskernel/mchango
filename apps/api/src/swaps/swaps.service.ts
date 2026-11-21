import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Db, isUniqueViolation, type Actor, type Queryable } from '../infra/database.js';
import { activeMembership } from '../groups/membership.js';

type UserActor = Actor & { id: string };

interface SwapRow {
  id: string;
  group_id: string;
  requester_membership_id: string;
  target_membership_id: string;
  requester_cycle_number: number;
  target_cycle_number: number;
  reason: string | null;
  status: 'pending' | 'accepted' | 'declined' | 'cancelled';
  created_at: Date;
  expires_at: Date;
  decided_at: Date | null;
  expired: boolean;
  requester_name?: string;
  target_name?: string;
}

const SWAP_COLUMNS = `s.id, s.group_id, s.requester_membership_id, s.target_membership_id,
  s.requester_cycle_number, s.target_cycle_number, s.reason, s.status, s.created_at, s.expires_at,
  s.decided_at, (s.status = 'pending' AND s.expires_at <= now()) AS expired`;

function toSwap(r: SwapRow) {
  return {
    id: r.id,
    groupId: r.group_id,
    requester: { membershipId: r.requester_membership_id, fullName: r.requester_name ?? null },
    target: { membershipId: r.target_membership_id, fullName: r.target_name ?? null },
    requesterCycleNumber: r.requester_cycle_number,
    targetCycleNumber: r.target_cycle_number,
    reason: r.reason,
    // Une demande sans réponse à temps expire : le silence ne vaut pas accord
    status: r.expired ? 'expired' : r.status,
    createdAt: r.created_at.toISOString(),
    expiresAt: r.expires_at.toISOString(),
    decidedAt: r.decided_at?.toISOString() ?? null,
  };
}

/** Tour d'un membre, avec ce qu'il faut savoir pour dire s'il peut encore changer de bénéficiaire. */
interface TurnState {
  id: string;
  cycle_number: number;
  status: string;
  due_date: string;
  declared: number;
}

/**
 * Échange de tour (spec/swaps.md). Deux membres échangent leurs places : chacun reçoit à la date
 * de l'autre. Il faut l'accord des deux ; aucun paiement ne doit déjà être déclaré pour l'un des
 * deux tours. Le reste du groupe n'a rien à faire : mêmes montants, mêmes dates.
 */
@Injectable()
export class SwapsService {
  constructor(private readonly db: Db) {}

  async list(userId: string, groupId: string) {
    if (!(await activeMembership(this.db, userId, groupId))) throw new NotFoundException('Groupe introuvable.');
    const { rows } = await this.db.query<SwapRow>(
      `SELECT ${SWAP_COLUMNS}, ru.full_name AS requester_name, tu.full_name AS target_name
       FROM turn_swaps s
       JOIN memberships rm ON rm.id = s.requester_membership_id JOIN users ru ON ru.id = rm.user_id
       JOIN memberships tm ON tm.id = s.target_membership_id JOIN users tu ON tu.id = tm.user_id
       WHERE s.group_id = $1
       ORDER BY s.created_at DESC LIMIT 50`,
      [groupId],
    );
    return rows.map(toSwap);
  }

  /** Le demandeur propose à [targetMembershipId] d'échanger leurs tours. */
  async request(actor: UserActor, groupId: string, input: { targetMembershipId: string; reason?: string }) {
    return this.db
      .transaction(actor, async (q) => {
        const me = await activeMembership(q, actor.id, groupId);
        if (!me) throw new NotFoundException('Groupe introuvable.');
        const target = input.targetMembershipId.toLowerCase();
        if (target === me.id) throw new BadRequestException('Choisissez un autre membre que vous-même.');
        await this.requireActiveGroup(q, groupId);
        const targetOk = await q.query(
          `SELECT 1 FROM memberships WHERE id = $1 AND group_id = $2 AND status = 'active'`,
          [target, groupId],
        );
        if (targetOk.rowCount !== 1) throw new NotFoundException('Ce membre ne fait pas partie du groupe.');

        const mine = await this.turnOf(q, groupId, me.id);
        const theirs = await this.turnOf(q, groupId, target);
        this.checkSwappable(mine, 'votre tour');
        this.checkSwappable(theirs, 'le tour de ce membre');

        const { rows } = await q.query<SwapRow>(
          `INSERT INTO turn_swaps AS s (group_id, requester_membership_id, target_membership_id,
                                        requester_cycle_number, target_cycle_number, reason)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING ${SWAP_COLUMNS}`,
          [groupId, me.id, target, mine.cycle_number, theirs.cycle_number, input.reason?.trim() || null],
        );
        return toSwap(rows[0]);
      })
      .catch((e: unknown) => {
        if (isUniqueViolation(e, 'uq_turn_swaps_pending')) {
          throw new ConflictException('Vous avez déjà une demande d\'échange en attente dans ce groupe.');
        }
        throw e;
      });
  }

  /** Réponse du membre sollicité (accept / decline) ou retrait par le demandeur (cancel). */
  async decide(actor: UserActor, swapId: string, decision: 'accept' | 'decline' | 'cancel') {
    return this.db.transaction(actor, async (q) => {
      const found = await q.query<SwapRow>(`SELECT ${SWAP_COLUMNS} FROM turn_swaps s WHERE s.id = $1 FOR UPDATE`, [swapId]);
      const s = found.rows[0];
      const me = s ? await activeMembership(q, actor.id, s.group_id) : null;
      if (!s || !me) throw new NotFoundException('Demande introuvable.');

      if (decision === 'cancel' && me.id !== s.requester_membership_id) {
        throw new ForbiddenException('Seul le demandeur retire sa demande.');
      }
      if (decision !== 'cancel' && me.id !== s.target_membership_id) {
        throw new ForbiddenException('Seul le membre sollicité répond à cette demande.');
      }
      if (s.status !== 'pending') throw new ConflictException('Cette demande a déjà reçu une réponse.');
      if (s.expired && decision === 'accept') {
        throw new ConflictException('Cette demande a expiré. Le demandeur peut en faire une nouvelle.');
      }

      if (decision === 'accept') {
        await this.requireActiveGroup(q, s.group_id);
        // Verrou sur les deux tours, dans un ordre fixe (pas d'interblocage entre deux échanges)
        const turns = await q.query<TurnState & { beneficiary_membership_id: string }>(
          `SELECT c.id, c.cycle_number, c.status, c.due_date::text AS due_date, c.beneficiary_membership_id,
                  (SELECT count(*)::int FROM contributions k WHERE k.cycle_id = c.id AND k.status <> 'rejected') AS declared
           FROM cycles c WHERE c.group_id = $1 AND c.cycle_number IN ($2, $3)
           ORDER BY c.cycle_number FOR UPDATE`,
          [s.group_id, s.requester_cycle_number, s.target_cycle_number],
        );
        const a = turns.rows.find((t) => t.cycle_number === s.requester_cycle_number)!;
        const b = turns.rows.find((t) => t.cycle_number === s.target_cycle_number)!;
        if (a.beneficiary_membership_id !== s.requester_membership_id || b.beneficiary_membership_id !== s.target_membership_id) {
          throw new ConflictException('Les tours ont changé depuis la demande : elle ne peut plus être acceptée.');
        }
        this.checkSwappable(a, 'le tour du demandeur');
        this.checkSwappable(b, 'votre tour');
      }

      const status = { accept: 'accepted', decline: 'declined', cancel: 'cancelled' }[decision];
      const updated = await q.query<SwapRow>(
        `UPDATE turn_swaps s SET status = $2::swap_status, decided_at = now() WHERE s.id = $1
         RETURNING ${SWAP_COLUMNS}`,
        [s.id, status],
      );

      if (decision === 'accept') {
        // Les deux bénéficiaires s'échangent dans une seule instruction ; l'unicité est vérifiée à la fin
        await q.query('SET CONSTRAINTS uq_cycles_beneficiary DEFERRED');
        await q.query(
          `UPDATE cycles SET beneficiary_membership_id =
             CASE cycle_number WHEN $2 THEN $5::uuid WHEN $3 THEN $4::uuid END
           WHERE group_id = $1 AND cycle_number IN ($2, $3)`,
          [s.group_id, s.requester_cycle_number, s.target_cycle_number, s.requester_membership_id, s.target_membership_id],
        );
        await q.query('SET CONSTRAINTS uq_cycles_beneficiary IMMEDIATE');
        // Les autres demandes en attente de ces deux membres portent sur des tours qui ont changé
        await q.query(
          `UPDATE turn_swaps SET status = 'cancelled', decided_at = now()
           WHERE group_id = $1 AND status = 'pending' AND id <> $2
             AND (requester_membership_id IN ($3, $4) OR target_membership_id IN ($3, $4))`,
          [s.group_id, s.id, s.requester_membership_id, s.target_membership_id],
        );
      }
      return toSwap(updated.rows[0]);
    });
  }

  private async requireActiveGroup(q: Queryable, groupId: string) {
    const { rows } = await q.query<{ status: string }>('SELECT status FROM groups WHERE id = $1', [groupId]);
    if (rows[0]?.status !== 'active') {
      throw new ConflictException(
        rows[0]?.status === 'draft'
          ? "Le groupe n'a pas encore démarré : le président peut encore changer l'ordre des tours."
          : 'Le groupe est terminé.',
      );
    }
  }

  private async turnOf(q: Queryable, groupId: string, membershipId: string): Promise<TurnState> {
    const { rows } = await q.query<TurnState>(
      `SELECT c.id, c.cycle_number, c.status, c.due_date::text AS due_date,
              (SELECT count(*)::int FROM contributions k WHERE k.cycle_id = c.id AND k.status <> 'rejected') AS declared
       FROM cycles c WHERE c.group_id = $1 AND c.beneficiary_membership_id = $2`,
      [groupId, membershipId],
    );
    if (!rows[0]) throw new ConflictException("Ce membre n'a pas de tour dans cette rotation.");
    return rows[0];
  }

  private checkSwappable(turn: TurnState, what: string) {
    if (turn.status !== 'open' && turn.status !== 'upcoming') {
      throw new ConflictException(`Échange impossible : ${what} (n°${turn.cycle_number}) est déjà passé.`);
    }
    if (turn.declared > 0) {
      throw new ConflictException(
        `Échange impossible : des paiements sont déjà déclarés pour ${what} (n°${turn.cycle_number}).`,
      );
    }
  }
}
