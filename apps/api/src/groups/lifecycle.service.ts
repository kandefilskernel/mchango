import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { appendAudit, Db, type Actor, type Queryable } from '../infra/database.js';
import { DRAW_ALGORITHM, drawTurnOrder, membersHash } from './draw.js';
import { GROUP_COLUMNS, toGroup, type GroupRow } from './groups.service.js';
import { activeMembership, TODAY_DRC_SQL } from './membership.js';

type UserActor = Actor & { id: string };

export interface UpdateGroupInput {
  name?: string;
  contributionAmountMinor?: number;
  frequency?: 'daily' | 'weekly' | 'monthly';
  startDate?: string;
  maxMembers?: number;
}

/** Préparation et démarrage d'un groupe : réservé au président, tant que le groupe est en brouillon. */
@Injectable()
export class GroupLifecycleService {
  constructor(private readonly db: Db) {}

  async update(actor: UserActor, groupId: string, input: UpdateGroupInput) {
    return this.db.transaction(actor, async (q) => {
      await this.lockDraftAsPresident(q, actor.id, groupId);
      if (input.maxMembers !== undefined && input.maxMembers < (await this.activeIds(q, groupId)).length) {
        throw new ConflictException('Le groupe compte déjà plus de membres que ce maximum.');
      }
      const { rows } = await q.query<GroupRow>(
        `UPDATE groups AS g SET
           name = coalesce($2, name),
           contribution_amount_minor = coalesce($3::bigint, contribution_amount_minor),
           frequency = coalesce($4::frequency_type, frequency),
           start_date = coalesce($5::date, start_date),
           max_members = coalesce($6::int, max_members)
         WHERE id = $1
         RETURNING ${GROUP_COLUMNS}`,
        [
          groupId,
          input.name ?? null,
          input.contributionAmountMinor ?? null,
          input.frequency ?? null,
          input.startDate ?? null,
          input.maxMembers ?? null,
        ],
      );
      return toGroup(rows[0]);
    });
  }

  /** Ordre choisi par le président : la liste doit contenir chaque membre actif une fois. */
  async setChosenOrder(actor: UserActor, groupId: string, membershipIds: string[]) {
    return this.db.transaction(actor, async (q) => {
      await this.lockDraftAsPresident(q, actor.id, groupId);
      const active = await this.activeIds(q, groupId);
      const given = membershipIds.map((id) => id.toLowerCase());
      if (
        given.length !== active.length ||
        new Set(given).size !== given.length ||
        given.some((id) => !active.includes(id))
      ) {
        throw new BadRequestException("La liste doit contenir chaque membre actif du groupe, une seule fois.");
      }
      await this.applyOrder(q, groupId, given);
      // Graine et membres d'un éventuel tirage précédent restent visibles : on voit qu'un
      // tirage a eu lieu puis a été remplacé, et il ne peut pas être relancé avec les mêmes membres.
      await q.query(`UPDATE groups SET turn_order_mode = 'chosen' WHERE id = $1`, [groupId]);
      await appendAudit(q, {
        groupId,
        actor,
        action: 'group.turn_order_set',
        payload: { mode: 'chosen', order: given },
      });
      return { mode: 'chosen' as const, order: await this.orderView(q, groupId) };
    });
  }

  /**
   * Tirage au sort vérifiable : graine aléatoire publiée, algorithme déterministe (spec/draw.md).
   * Un seul tirage par liste de membres : le président ne peut pas relancer jusqu'à obtenir
   * l'ordre qui l'arrange. Il ne redevient possible que si les membres changent.
   */
  async draw(actor: UserActor, groupId: string) {
    return this.db.transaction(actor, async (q) => {
      await this.lockDraftAsPresident(q, actor.id, groupId);
      const active = await this.activeIds(q, groupId);
      if (active.length < 2) throw new ConflictException('Il faut au moins 2 membres pour le tirage.');

      const hash = membersHash(active);
      const previous = await q.query<{ turn_order_mode: string | null; draw_members_hash: string | null }>(
        'SELECT turn_order_mode, draw_members_hash FROM groups WHERE id = $1',
        [groupId],
      );
      if (previous.rows[0].draw_members_hash === hash) {
        throw new ConflictException(
          'Le tirage a déjà eu lieu pour ces membres. Il ne peut être refait que si la liste des membres change.',
        );
      }

      const seed = randomBytes(32).toString('hex');
      const order = drawTurnOrder(active, seed);
      await this.applyOrder(q, groupId, order);
      // Le hash des membres est gardé même si le président passe ensuite à un ordre choisi :
      // il ne pourra pas retirer au sort avec les mêmes membres.
      await q.query(
        `UPDATE groups SET turn_order_mode = 'draw', draw_seed = $2, draw_members_hash = $3
         WHERE id = $1`,
        [groupId, seed, hash],
      );
      await appendAudit(q, {
        groupId,
        actor,
        action: 'group.turn_order_set',
        payload: { mode: 'draw', algorithm: DRAW_ALGORITHM, seed, members_hash: hash, order },
      });
      return {
        mode: 'draw' as const,
        algorithm: DRAW_ALGORITHM,
        seed,
        membersHash: hash,
        order: await this.orderView(q, groupId),
      };
    });
  }

  /** Démarre le groupe : un cycle par membre, dans l'ordre des tours. Les invitations sont closes. */
  async start(actor: UserActor, groupId: string) {
    return this.db.transaction(actor, async (q) => {
      await this.lockDraftAsPresident(q, actor.id, groupId);
      const check = await q.query<{ members: number; ordered: number; max_turn: number | null; date_ok: boolean }>(
        `SELECT count(*)::int AS members, count(m.turn_order)::int AS ordered,
                max(m.turn_order) AS max_turn,
                (SELECT start_date >= ${TODAY_DRC_SQL} FROM groups WHERE id = $1) AS date_ok
         FROM memberships m WHERE m.group_id = $1 AND m.status = 'active'`,
        [groupId],
      );
      const { members, ordered, max_turn, date_ok } = check.rows[0];
      if (members < 2) throw new ConflictException('Il faut au moins 2 membres pour démarrer.');
      // turn_order unique et > 0 : count = max = N équivaut à « exactement 1..N »
      if (ordered !== members || max_turn !== members) {
        throw new ConflictException(
          "Fixez l'ordre des tours (choisi ou tiré au sort) pour tous les membres avant de démarrer.",
        );
      }
      if (!date_ok) {
        throw new ConflictException('La date de début est passée : modifiez-la avant de démarrer.');
      }

      await q.query(
        `INSERT INTO cycles (group_id, cycle_number, due_date, beneficiary_membership_id, status)
         SELECT m.group_id, m.turn_order,
                (g.start_date + CASE g.frequency
                   WHEN 'daily'  THEN make_interval(days   => m.turn_order - 1)
                   WHEN 'weekly' THEN make_interval(weeks  => m.turn_order - 1)
                   -- calculé depuis la date de début : 31 jan → 28 fév → 31 mars
                   ELSE               make_interval(months => m.turn_order - 1)
                 END)::date,
                m.id,
                (CASE WHEN m.turn_order = 1 THEN 'open' ELSE 'upcoming' END)::cycle_status
         FROM memberships m JOIN groups g ON g.id = m.group_id
         WHERE m.group_id = $1 AND m.status = 'active'`,
        [groupId],
      );
      await q.query(`UPDATE groups SET status = 'active', started_at = now() WHERE id = $1`, [groupId]);
      await q.query(
        'UPDATE invitations SET revoked_at = now() WHERE group_id = $1 AND revoked_at IS NULL',
        [groupId],
      );
      const group = await q.query<GroupRow>(`SELECT ${GROUP_COLUMNS} FROM groups g WHERE g.id = $1`, [groupId]);
      return { ...toGroup(group.rows[0]), cycleCount: members };
    });
  }

  private async lockDraftAsPresident(q: Queryable, userId: string, groupId: string) {
    const membership = await activeMembership(q, userId, groupId);
    if (!membership) throw new NotFoundException('Groupe introuvable.');
    if (membership.role !== 'president') {
      throw new ForbiddenException('Seul le président peut préparer et démarrer le groupe.');
    }
    const { rows } = await q.query<{ status: string }>(
      'SELECT status FROM groups WHERE id = $1 FOR UPDATE',
      [groupId],
    );
    if (rows[0].status !== 'draft') {
      throw new ConflictException('Le groupe a déjà démarré : ses règles et son ordre sont figés.');
    }
  }

  private async activeIds(q: Queryable, groupId: string): Promise<string[]> {
    const { rows } = await q.query<{ id: string }>(
      `SELECT id FROM memberships WHERE group_id = $1 AND status = 'active'`,
      [groupId],
    );
    return rows.map((r) => r.id);
  }

  private async applyOrder(q: Queryable, groupId: string, orderedIds: string[]) {
    // D'abord tout vider : l'unicité (group_id, turn_order) est vérifiée ligne par ligne
    await q.query(
      'UPDATE memberships SET turn_order = NULL WHERE group_id = $1 AND turn_order IS NOT NULL',
      [groupId],
    );
    await q.query(
      `UPDATE memberships m SET turn_order = o.position
       FROM unnest($2::uuid[]) WITH ORDINALITY AS o(id, position)
       WHERE m.id = o.id AND m.group_id = $1`,
      [groupId, orderedIds],
    );
  }

  private async orderView(q: Queryable, groupId: string) {
    const { rows } = await q.query<{ turn_order: number; membership_id: string; full_name: string }>(
      `SELECT m.turn_order, m.id AS membership_id, u.full_name
       FROM memberships m JOIN users u ON u.id = m.user_id
       WHERE m.group_id = $1 AND m.status = 'active'
       ORDER BY m.turn_order`,
      [groupId],
    );
    return rows.map((r) => ({ turn: r.turn_order, membershipId: r.membership_id, fullName: r.full_name }));
  }
}
