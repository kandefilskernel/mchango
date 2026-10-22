import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Redis } from 'ioredis';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { appendAudit, Db, type Actor, type Queryable } from '../infra/database.js';
import { REDIS } from '../infra/redis.js';
import { generateInviteCode, inviteCodeHash, normalizeInviteCode } from './invite-code.js';
import { activeMembership } from './membership.js';

/** Essais de code d'invitation par utilisateur et par heure (contre le devinage). */
const JOIN_ATTEMPTS_PER_HOUR = 10;

export interface CreateGroupInput {
  name: string;
  type: 'formel' | 'informel';
  currency: 'CDF' | 'USD';
  contributionAmountMinor: number;
  frequency: 'daily' | 'weekly' | 'monthly';
  startDate: string;
  maxMembers: number;
}

export interface GroupRow {
  id: string;
  name: string;
  type: string;
  currency: string;
  contribution_amount_minor: string;
  frequency: string;
  payout_mode: string;
  start_date: string;
  status: string;
  max_members: number;
  turn_order_mode: string | null;
  draw_seed: string | null;
  started_at: Date | null;
  created_at: Date;
}

export const GROUP_COLUMNS = `g.id, g.name, g.type, g.currency, g.contribution_amount_minor,
  g.frequency, g.payout_mode, g.start_date::text AS start_date, g.status, g.max_members,
  g.turn_order_mode, g.draw_seed, g.started_at, g.created_at`;

export function toGroup(row: GroupRow) {
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    currency: row.currency,
    // BIGINT arrive en texte ; plafonné à 10^12 à la création, donc exact en number
    contributionAmountMinor: Number(row.contribution_amount_minor),
    frequency: row.frequency,
    payoutMode: row.payout_mode,
    startDate: row.start_date,
    status: row.status,
    maxMembers: row.max_members,
    turnOrderMode: row.turn_order_mode,
    // Publiée pour que chaque membre puisse refaire le tirage (spec/draw.md)
    drawSeed: row.draw_seed,
    startedAt: row.started_at?.toISOString() ?? null,
    createdAt: row.created_at.toISOString(),
  };
}

@Injectable()
export class GroupsService {
  constructor(
    private readonly db: Db,
    @Inject(REDIS) private readonly redis: Redis,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  /** Crée le groupe (brouillon) ; son créateur en devient le président. */
  async create(actor: Actor & { id: string }, input: CreateGroupInput) {
    return this.db.transaction(actor, async (q) => {
      const { rows } = await q.query<GroupRow>(
        `INSERT INTO groups AS g (name, type, currency, contribution_amount_minor, frequency,
                                  start_date, max_members, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING ${GROUP_COLUMNS}`,
        [
          input.name,
          input.type,
          input.currency,
          input.contributionAmountMinor,
          input.frequency,
          input.startDate,
          input.maxMembers,
          actor.id,
        ],
      );
      await q.query(
        `INSERT INTO memberships (group_id, user_id, role, status, rules_accepted_at)
         VALUES ($1, $2, 'president', 'active', now())`,
        [rows[0].id, actor.id],
      );
      return { ...toGroup(rows[0]), myRole: 'president', memberCount: 1 };
    });
  }

  async listMine(userId: string) {
    const { rows } = await this.db.query<GroupRow & { role: string; member_count: number }>(
      `SELECT ${GROUP_COLUMNS}, m.role,
              (SELECT count(*)::int FROM memberships x
               WHERE x.group_id = g.id AND x.status = 'active') AS member_count
       FROM memberships m JOIN groups g ON g.id = m.group_id
       WHERE m.user_id = $1 AND m.status = 'active'
       ORDER BY g.created_at DESC`,
      [userId],
    );
    return rows.map((r) => ({ ...toGroup(r), myRole: r.role, memberCount: r.member_count }));
  }

  /** Détail d'un groupe, réservé à ses membres actifs (404 sinon : ne révèle pas son existence). */
  async getForMember(userId: string, groupId: string) {
    const role = await this.activeRole(this.db, userId, groupId);
    if (!role) throw new NotFoundException('Groupe introuvable.');
    const group = await this.db.query<GroupRow>(
      `SELECT ${GROUP_COLUMNS} FROM groups g WHERE g.id = $1`,
      [groupId],
    );
    const members = await this.db.query<{
      membership_id: string;
      user_id: string;
      full_name: string;
      phone: string;
      role: string;
      turn_order: number | null;
      joined_at: Date;
    }>(
      `SELECT m.id AS membership_id, u.id AS user_id, u.full_name, u.phone, m.role,
              m.turn_order, m.joined_at
       FROM memberships m JOIN users u ON u.id = m.user_id
       WHERE m.group_id = $1 AND m.status = 'active'
       ORDER BY m.turn_order NULLS LAST, m.joined_at`,
      [groupId],
    );
    return {
      ...toGroup(group.rows[0]),
      myRole: role,
      memberCount: members.rowCount,
      // Les numéros ne sont visibles que des membres du même groupe
      members: members.rows.map((m) => ({
        membershipId: m.membership_id,
        userId: m.user_id,
        fullName: m.full_name,
        phone: m.phone,
        role: m.role,
        turnOrder: m.turn_order,
        joinedAt: m.joined_at.toISOString(),
      })),
    };
  }

  /** Code d'invitation à partager. Réservé au président, tant que le groupe n'a pas démarré. */
  async createInvitation(
    actor: Actor & { id: string },
    groupId: string,
    input: { validHours: number; maxUses: number | null },
  ) {
    return this.db.transaction(actor, async (q) => {
      const role = await this.activeRole(q, actor.id, groupId);
      if (!role) throw new NotFoundException('Groupe introuvable.');
      if (role !== 'president') {
        throw new ForbiddenException('Seul le président peut inviter de nouveaux membres.');
      }
      const group = await q.query<{ name: string; status: string }>(
        'SELECT name, status FROM groups WHERE id = $1',
        [groupId],
      );
      if (group.rows[0].status !== 'draft') {
        throw new ConflictException('Le groupe a déjà démarré : on ne peut plus inviter.');
      }

      const code = generateInviteCode();
      const { rows } = await q.query<{ id: string; expires_at: Date }>(
        `INSERT INTO invitations (group_id, invited_by, token_hash, expires_at, max_uses)
         VALUES ($1, $2, $3, now() + make_interval(hours => $4), $5)
         RETURNING id, expires_at`,
        [
          groupId,
          actor.id,
          inviteCodeHash(normalizeInviteCode(code)!, this.config.OTP_PEPPER),
          input.validHours,
          input.maxUses,
        ],
      );
      const invitation = rows[0];
      // Le code lui-même n'entre jamais dans le journal
      await appendAudit(q, {
        groupId,
        actor,
        action: 'group.invitation_created',
        payload: {
          invitation_id: invitation.id,
          expires_at: invitation.expires_at.toISOString(),
          max_uses: input.maxUses,
        },
      });

      const until = new Intl.DateTimeFormat('fr-FR', {
        timeZone: 'Africa/Lubumbashi',
        dateStyle: 'long',
        timeStyle: 'short',
      }).format(invitation.expires_at);
      return {
        invitationId: invitation.id,
        code,
        expiresAt: invitation.expires_at.toISOString(),
        maxUses: input.maxUses,
        shareText:
          `Rejoins notre tontine « ${group.rows[0].name} » sur Mchango avec le code ${code} ` +
          `(valable jusqu'au ${until}).`,
      };
    });
  }

  /** Rejoindre un groupe avec un code, en acceptant son règlement. */
  /**
   * Ce que le code d'invitation donne à voir avant de rejoindre : les règles à accepter.
   * Compte dans la limite d'essais de code, comme join().
   */
  async preview(userId: string, rawCode: string) {
    await this.limitJoinAttempts(userId);
    const code = normalizeInviteCode(rawCode);
    const { rows } = await this.db.query<
      GroupRow & { president_name: string; member_count: number }
    >(
      `SELECT ${GROUP_COLUMNS},
              (SELECT u.full_name FROM memberships m JOIN users u ON u.id = m.user_id
               WHERE m.group_id = g.id AND m.role = 'president' AND m.status = 'active'
               LIMIT 1) AS president_name,
              (SELECT count(*)::int FROM memberships m
               WHERE m.group_id = g.id AND m.status = 'active') AS member_count
       FROM invitations i JOIN groups g ON g.id = i.group_id
       WHERE i.token_hash = $1 AND i.revoked_at IS NULL AND i.expires_at > now()
         AND (i.max_uses IS NULL OR i.uses < i.max_uses)`,
      [code ? inviteCodeHash(code, this.config.OTP_PEPPER) : ''],
    );
    const r = rows[0];
    if (!r) throw new NotFoundException("Code d'invitation invalide ou expiré.");
    const g = toGroup(r);
    return {
      name: g.name,
      type: g.type,
      currency: g.currency,
      contributionAmountMinor: g.contributionAmountMinor,
      frequency: g.frequency,
      payoutMode: g.payoutMode,
      startDate: g.startDate,
      status: g.status,
      maxMembers: g.maxMembers,
      memberCount: r.member_count,
      presidentName: r.president_name,
    };
  }

  async join(actor: Actor & { id: string }, input: { code: string; acceptRules: boolean }) {
    await this.limitJoinAttempts(actor.id);
    if (!input.acceptRules) {
      throw new BadRequestException('Il faut accepter le règlement du groupe pour le rejoindre.');
    }
    const code = normalizeInviteCode(input.code);
    const invalid = new NotFoundException("Code d'invitation invalide ou expiré.");
    if (!code) throw invalid;

    return this.db.transaction(actor, async (q) => {
      const found = await q.query<{ id: string; group_id: string; max_uses: number | null; uses: number }>(
        `SELECT id, group_id, max_uses, uses FROM invitations
         WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()
         FOR UPDATE`,
        [inviteCodeHash(code, this.config.OTP_PEPPER)],
      );
      const invitation = found.rows[0];
      if (!invitation) throw invalid;
      if (invitation.max_uses !== null && invitation.uses >= invitation.max_uses) {
        throw new ConflictException("Ce code d'invitation a déjà été utilisé le nombre de fois prévu.");
      }

      // Verrou sur le groupe : deux arrivées simultanées ne dépassent pas la taille maximale
      const group = await q.query<{ status: string; max_members: number }>(
        'SELECT status, max_members FROM groups WHERE id = $1 FOR UPDATE',
        [invitation.group_id],
      );
      if (group.rows[0].status !== 'draft') {
        throw new ConflictException('Le groupe a déjà démarré : on ne peut plus le rejoindre.');
      }
      const existing = await q.query<{ status: string }>(
        'SELECT status FROM memberships WHERE group_id = $1 AND user_id = $2',
        [invitation.group_id, actor.id],
      );
      if (existing.rows[0]?.status === 'active') {
        throw new ConflictException('Vous êtes déjà membre de ce groupe.');
      }
      if (existing.rows[0]) {
        throw new ForbiddenException(
          'Vous avez quitté ou été retiré de ce groupe. Demandez au président de vous réintégrer.',
        );
      }
      const count = await q.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM memberships WHERE group_id = $1 AND status = 'active'`,
        [invitation.group_id],
      );
      if (count.rows[0].n >= group.rows[0].max_members) {
        throw new ConflictException('Le groupe est complet.');
      }

      await q.query(
        `INSERT INTO memberships (group_id, user_id, role, status, rules_accepted_at)
         VALUES ($1, $2, 'member', 'active', now())`,
        [invitation.group_id, actor.id],
      );
      await q.query('UPDATE invitations SET uses = uses + 1 WHERE id = $1', [invitation.id]);
      return { groupId: invitation.group_id };
    });
  }

  private async activeRole(q: Queryable, userId: string, groupId: string): Promise<string | null> {
    return (await activeMembership(q, userId, groupId))?.role ?? null;
  }

  private async limitJoinAttempts(userId: string) {
    const key = `rl:join:${userId}`;
    const count = await this.redis.incr(key);
    if (count === 1) await this.redis.expire(key, 3600);
    if (count > JOIN_ATTEMPTS_PER_HOUR) {
      throw new HttpException(
        "Trop d'essais de code d'invitation. Réessayez dans une heure.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }
}
