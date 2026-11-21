import { Injectable, NotFoundException } from '@nestjs/common';
import { Db, type Actor } from '../infra/database.js';
import { activeMembership } from '../groups/membership.js';

type UserActor = Actor & { id: string };

export const GOAL_KINDS = ['school', 'business', 'housing', 'health', 'family', 'equipment', 'other'] as const;
export type GoalKind = (typeof GOAL_KINDS)[number];

export interface GoalInput {
  kind: GoalKind;
  label: string;
  targetAmountMinor?: number | null;
  targetDate?: string | null;
  sharedWithGroup: boolean;
}

export interface GoalRow {
  kind: GoalKind;
  label: string;
  target_amount_minor: string | null;
  target_date: string | null;
  shared_with_group: boolean;
  updated_at: Date;
}

export const GOAL_COLUMNS = `s.kind, s.label, s.target_amount_minor, s.target_date::text AS target_date,
  s.shared_with_group, s.updated_at`;

export function toGoal(r: GoalRow) {
  return {
    kind: r.kind,
    label: r.label,
    targetAmountMinor: r.target_amount_minor === null ? null : Number(r.target_amount_minor),
    targetDate: r.target_date,
    sharedWithGroup: r.shared_with_group,
    updatedAt: r.updated_at.toISOString(),
  };
}

/**
 * Objectif d'épargne d'un membre pour une tontine (spec/goals.md) : ce qu'il fera de la mise reçue
 * à son tour. Personnel ; visible du groupe seulement s'il le choisit. La progression se calcule à
 * partir des cotisations confirmées (voir le carnet) : rien n'est stocké comme solde.
 */
@Injectable()
export class GoalsService {
  constructor(private readonly db: Db) {}

  async get(userId: string, groupId: string) {
    const me = await activeMembership(this.db, userId, groupId);
    if (!me) throw new NotFoundException('Groupe introuvable.');
    const { rows } = await this.db.query<GoalRow>(
      `SELECT ${GOAL_COLUMNS} FROM savings_goals s WHERE s.membership_id = $1 AND s.archived_at IS NULL`,
      [me.id],
    );
    return { goal: rows[0] ? toGoal(rows[0]) : null };
  }

  async set(actor: UserActor, groupId: string, input: GoalInput) {
    return this.db.transaction(actor, async (q) => {
      const me = await activeMembership(q, actor.id, groupId);
      if (!me) throw new NotFoundException('Groupe introuvable.');
      const { rows } = await q.query<GoalRow>(
        `INSERT INTO savings_goals AS s (user_id, membership_id, kind, label, target_amount_minor, target_date,
                                         shared_with_group)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (membership_id) DO UPDATE SET
           kind = EXCLUDED.kind, label = EXCLUDED.label, target_amount_minor = EXCLUDED.target_amount_minor,
           target_date = EXCLUDED.target_date, shared_with_group = EXCLUDED.shared_with_group,
           archived_at = NULL, updated_at = now()
         RETURNING ${GOAL_COLUMNS}`,
        [
          actor.id,
          me.id,
          input.kind,
          input.label.trim(),
          input.targetAmountMinor ?? null,
          input.targetDate ?? null,
          input.sharedWithGroup,
        ],
      );
      return { goal: toGoal(rows[0]) };
    });
  }

  /** Retire l'objectif (il reste dans le journal du membre). */
  async archive(actor: UserActor, groupId: string) {
    await this.db.transaction(actor, async (q) => {
      const me = await activeMembership(q, actor.id, groupId);
      if (!me) throw new NotFoundException('Groupe introuvable.');
      await q.query(
        `UPDATE savings_goals SET archived_at = now(), updated_at = now()
         WHERE membership_id = $1 AND archived_at IS NULL`,
        [me.id],
      );
    });
  }
}
