import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { appendAudit, Db, type Queryable } from '../infra/database.js';
import { TODAY_DRC_SQL } from '../groups/membership.js';
import { SEES_PHONE_NUMBERS } from './staff.guard.js';
import type { StaffMember } from './staff-auth.service.js';

/** +243991234567 → +243 99 *** **67 pour les rôles qui n'ont pas besoin du numéro complet. */
export function maskPhone(phone: string): string {
  return phone.length < 8 ? '***' : `${phone.slice(0, 4)} ${phone.slice(4, 6)} *** **${phone.slice(-2)}`;
}

const iso = (d: Date | null | undefined) => d?.toISOString() ?? null;

/**
 * Lectures et décisions de l'équipe. Toute décision est journalisée avec l'acteur « staff » ;
 * celles qui concernent un groupe vont dans la chaîne de ce groupe, visible de ses membres.
 * L'équipe ne peut jamais confirmer un paiement à la place du bénéficiaire.
 */
@Injectable()
export class AdminService {
  constructor(private readonly db: Db) {}

  private phone(staff: StaffMember, phone: string) {
    return SEES_PHONE_NUMBERS.includes(staff.role) ? phone : maskPhone(phone);
  }

  // ---------- Tableau de bord ----------

  async dashboard() {
    const { rows } = await this.db.query<Record<string, number>>(
      `SELECT
         (SELECT count(*)::int FROM users) AS users_total,
         (SELECT count(*)::int FROM users WHERE created_at > now() - interval '7 days') AS users_new_7d,
         (SELECT count(*)::int FROM users WHERE is_blocked) AS users_blocked,
         (SELECT count(*)::int FROM groups WHERE status = 'draft') AS groups_draft,
         (SELECT count(*)::int FROM groups WHERE status = 'active') AS groups_active,
         (SELECT count(*)::int FROM groups WHERE status = 'suspended') AS groups_suspended,
         (SELECT count(*)::int FROM groups WHERE status = 'closed') AS groups_closed,
         (SELECT count(*)::int FROM contributions
            WHERE (declared_at AT TIME ZONE 'Africa/Lubumbashi')::date = ${TODAY_DRC_SQL}) AS contributions_declared_today,
         (SELECT count(*)::int FROM confirmations
            WHERE decision = 'confirm' AND (confirmed_at AT TIME ZONE 'Africa/Lubumbashi')::date = ${TODAY_DRC_SQL})
            AS contributions_confirmed_today,
         (SELECT count(*)::int FROM disputes WHERE status = 'open') AS disputes_open,
         (SELECT count(*)::int FROM pin_reset_requests WHERE status = 'pending' AND expires_at > now()) AS pin_resets_pending,
         (SELECT count(*)::int FROM notifications WHERE status = 'failed' AND created_at > now() - interval '7 days')
            AS notifications_failed_7d`,
    );
    // Retards : paiements attendus sur des tours échus depuis 30 jours, sans déclaration valable
    const late = await this.db.query<{ expected: number; missing: number }>(
      `SELECT count(*)::int AS expected,
              count(*) FILTER (WHERE NOT EXISTS (
                SELECT 1 FROM contributions k
                WHERE k.cycle_id = c.id AND k.payer_membership_id = m.id AND k.status <> 'rejected'))::int AS missing
       FROM cycles c
       JOIN groups g ON g.id = c.group_id AND g.status = 'active'
       JOIN memberships m ON m.group_id = c.group_id AND m.status = 'active' AND m.id <> c.beneficiary_membership_id
       WHERE c.due_date < ${TODAY_DRC_SQL} AND c.due_date >= ${TODAY_DRC_SQL} - 30`,
    );
    const { expected, missing } = late.rows[0];
    return {
      ...rows[0],
      late_payments_30d: missing,
      late_rate_30d: expected === 0 ? null : Math.round((missing / expected) * 1000) / 10,
    };
  }

  // ---------- À traiter (support) ----------

  /** Tout ce qui attend une personne de l'équipe, du plus urgent au moins urgent. */
  async inbox(staff: StaffMember) {
    const [disputes, pinLocked, pinResets, smsFailed, suspended] = await Promise.all([
      this.db.query<{ n: number }>(`SELECT count(*)::int AS n FROM disputes WHERE status = 'open'`),
      this.db.query<{ id: string; full_name: string; phone: string; pin_locked_until: Date }>(
        `SELECT id, full_name, phone, pin_locked_until FROM users
         WHERE pin_locked_until > now() ORDER BY pin_locked_until LIMIT 20`,
      ),
      this.db.query<{ id: string; user_id: string; full_name: string; phone: string; created_at: Date; expires_at: Date }>(
        `SELECT r.id, r.user_id, u.full_name, u.phone, r.created_at, r.expires_at
         FROM pin_reset_requests r JOIN users u ON u.id = r.user_id
         WHERE r.status = 'pending' AND r.expires_at > now() ORDER BY r.created_at LIMIT 20`,
      ),
      this.db.query<{ id: string; user_id: string; full_name: string; phone: string; template: string; error: string | null; created_at: Date }>(
        `SELECT n.id, n.user_id, u.full_name, u.phone, n.template, n.error, n.created_at
         FROM notifications n JOIN users u ON u.id = n.user_id
         WHERE n.status = 'failed' AND n.created_at > now() - interval '7 days'
         ORDER BY n.created_at DESC LIMIT 20`,
      ),
      this.db.query<{ id: string; name: string; suspended_reason: string | null }>(
        `SELECT id, name, suspended_reason FROM groups WHERE status = 'suspended' ORDER BY created_at DESC LIMIT 20`,
      ),
    ]);
    const counts = {
      disputesOpen: disputes.rows[0].n,
      pinLocked: pinLocked.rowCount ?? 0,
      pinResetsPending: pinResets.rowCount ?? 0,
      smsFailed: smsFailed.rowCount ?? 0,
      groupsSuspended: suspended.rowCount ?? 0,
    };
    return {
      counts: { ...counts, total: Object.values(counts).reduce((a, b) => a + b, 0) },
      pinLocked: pinLocked.rows.map((r) => ({
        userId: r.id,
        fullName: r.full_name,
        phone: this.phone(staff, r.phone),
        lockedUntil: iso(r.pin_locked_until),
      })),
      pinResets: pinResets.rows.map((r) => ({
        requestId: r.id,
        userId: r.user_id,
        fullName: r.full_name,
        phone: this.phone(staff, r.phone),
        createdAt: iso(r.created_at),
        expiresAt: iso(r.expires_at),
        // Plus de 24 h sans réponse du garant : la personne a sans doute besoin d'aide
        waitingLong: Date.now() - r.created_at.getTime() > 24 * 3600_000,
      })),
      smsFailed: smsFailed.rows.map((r) => ({
        id: r.id,
        userId: r.user_id,
        fullName: r.full_name,
        phone: this.phone(staff, r.phone),
        template: r.template,
        error: r.error,
        createdAt: iso(r.created_at),
      })),
      groupsSuspended: suspended.rows.map((r) => ({ id: r.id, name: r.name, reason: r.suspended_reason })),
    };
  }

  /** PIN bloqué après 5 essais : la personne peut réessayer tout de suite (journalisé). */
  async unlockPin(staff: StaffMember, userId: string) {
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rowCount } = await q.query(
        'UPDATE users SET pin_failed_attempts = 0, pin_locked_until = NULL WHERE id = $1 AND pin_locked_until IS NOT NULL',
        [userId],
      );
      if (rowCount !== 1) throw new NotFoundException("Ce compte n'a pas de PIN bloqué.");
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: staff.id },
        action: 'staff.pin_unlocked',
        payload: { user_id: userId },
      });
      return { unlocked: true };
    });
  }

  // ---------- Utilisateurs ----------

  async searchUsers(staff: StaffMember, q: string) {
    const digits = q.replace(/\D/g, '');
    const { rows } = await this.db.query<{
      id: string;
      full_name: string;
      phone: string;
      is_blocked: boolean;
      created_at: Date;
      groups: number;
    }>(
      `SELECT u.id, u.full_name, u.phone, u.is_blocked, u.created_at,
              (SELECT count(*)::int FROM memberships m WHERE m.user_id = u.id AND m.status = 'active') AS groups
       FROM users u
       WHERE $1 = '' OR u.full_name ILIKE '%' || $1 || '%' OR ($2 <> '' AND u.phone LIKE '%' || $2 || '%')
       ORDER BY u.created_at DESC LIMIT 50`,
      [q.trim(), digits.length >= 4 ? digits : ''],
    );
    return rows.map((r) => ({
      id: r.id,
      fullName: r.full_name,
      phone: this.phone(staff, r.phone),
      isBlocked: r.is_blocked,
      createdAt: iso(r.created_at),
      groups: r.groups,
    }));
  }

  async user(staff: StaffMember, userId: string) {
    const u = await this.db.query<{
      id: string;
      full_name: string;
      phone: string;
      language: string;
      is_blocked: boolean;
      blocked_reason: string | null;
      pin_locked_until: Date | null;
      created_at: Date;
    }>(
      `SELECT id, full_name, phone, language, is_blocked, blocked_reason, pin_locked_until, created_at
       FROM users WHERE id = $1`,
      [userId],
    );
    if (!u.rows[0]) throw new NotFoundException('Utilisateur introuvable.');
    const [devices, memberships, events] = await Promise.all([
      this.db.query<{ id: string; created_at: Date; last_seen_at: Date | null; revoked_at: Date | null }>(
        'SELECT id, created_at, last_seen_at, revoked_at FROM devices WHERE user_id = $1 ORDER BY created_at DESC',
        [userId],
      ),
      this.db.query<{ group_id: string; name: string; group_status: string; role: string; status: string }>(
        `SELECT g.id AS group_id, g.name, g.status AS group_status, m.role, m.status
         FROM memberships m JOIN groups g ON g.id = m.group_id WHERE m.user_id = $1 ORDER BY m.joined_at DESC`,
        [userId],
      ),
      this.db.query<{ seq: string; action: string; created_at: Date; actor_type: string }>(
        `SELECT seq, action, created_at, actor_type FROM audit_log
         WHERE chain_id = 'global' AND payload::jsonb ->> 'user_id' = $1 ORDER BY seq DESC LIMIT 30`,
        [userId],
      ),
    ]);
    const r = u.rows[0];
    return {
      id: r.id,
      fullName: r.full_name,
      phone: this.phone(staff, r.phone),
      language: r.language,
      isBlocked: r.is_blocked,
      blockedReason: r.blocked_reason,
      pinLockedUntil: iso(r.pin_locked_until),
      createdAt: iso(r.created_at),
      devices: devices.rows.map((d) => ({
        id: d.id,
        createdAt: iso(d.created_at),
        lastSeenAt: iso(d.last_seen_at),
        revokedAt: iso(d.revoked_at),
      })),
      memberships: memberships.rows.map((m) => ({
        groupId: m.group_id,
        groupName: m.name,
        groupStatus: m.group_status,
        role: m.role,
        status: m.status,
      })),
      events: events.rows.map((e) => ({ seq: Number(e.seq), action: e.action, actorType: e.actor_type, createdAt: iso(e.created_at) })),
    };
  }

  /** Bloque ou débloque un compte. Bloquer coupe les sessions : plus de défi signé accepté. */
  async setUserBlocked(staff: StaffMember, userId: string, blocked: boolean, reason: string) {
    if (blocked && reason.trim().length < 5) throw new BadRequestException('Indiquez le motif du blocage.');
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rowCount } = await q.query(
        'UPDATE users SET is_blocked = $2, blocked_reason = $3 WHERE id = $1',
        [userId, blocked, blocked ? reason.trim() : null],
      );
      if (rowCount !== 1) throw new NotFoundException('Utilisateur introuvable.');
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: staff.id },
        action: blocked ? 'staff.user_blocked' : 'staff.user_unblocked',
        payload: { user_id: userId, reason: reason.trim() || null },
      });
      return { isBlocked: blocked };
    });
  }

  /** Téléphone perdu ou volé : l'appareil ne peut plus ouvrir de session. */
  async revokeDevice(staff: StaffMember, userId: string, deviceId: string) {
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rowCount } = await q.query(
        'UPDATE devices SET revoked_at = now() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL',
        [deviceId, userId],
      );
      if (rowCount !== 1) throw new NotFoundException('Appareil introuvable ou déjà révoqué.');
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: staff.id },
        action: 'staff.device_revoked',
        payload: { user_id: userId, device_id: deviceId },
      });
      return { revoked: true };
    });
  }

  // ---------- Groupes ----------

  async searchGroups(q: string, status: string) {
    const { rows } = await this.db.query<{
      id: string;
      name: string;
      status: string;
      currency: string;
      amount: string;
      frequency: string;
      created_at: Date;
      members: number;
      president: string | null;
      open_disputes: number;
    }>(
      `SELECT g.id, g.name, g.status, g.currency, g.contribution_amount_minor AS amount, g.frequency, g.created_at,
              (SELECT count(*)::int FROM memberships m WHERE m.group_id = g.id AND m.status = 'active') AS members,
              (SELECT u.full_name FROM memberships m JOIN users u ON u.id = m.user_id
               WHERE m.group_id = g.id AND m.role = 'president' LIMIT 1) AS president,
              (SELECT count(*)::int FROM disputes d JOIN contributions k ON k.id = d.contribution_id
               WHERE k.group_id = g.id AND d.status = 'open') AS open_disputes
       FROM groups g
       WHERE ($1 = '' OR g.name ILIKE '%' || $1 || '%') AND ($2 = '' OR g.status::text = $2)
       ORDER BY g.created_at DESC LIMIT 50`,
      [q.trim(), status],
    );
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      status: r.status,
      currency: r.currency,
      contributionAmountMinor: Number(r.amount),
      frequency: r.frequency,
      createdAt: iso(r.created_at),
      members: r.members,
      president: r.president,
      openDisputes: r.open_disputes,
    }));
  }

  async group(staff: StaffMember, groupId: string) {
    const g = await this.db.query<{
      id: string;
      name: string;
      status: string;
      currency: string;
      amount: string;
      frequency: string;
      start_date: string;
      turn_order_mode: string | null;
      draw_seed: string | null;
      suspended_reason: string | null;
      created_at: Date;
    }>(
      `SELECT id, name, status, currency, contribution_amount_minor AS amount, frequency, start_date::text AS start_date,
              turn_order_mode, draw_seed, suspended_reason, created_at
       FROM groups WHERE id = $1`,
      [groupId],
    );
    if (!g.rows[0]) throw new NotFoundException('Groupe introuvable.');
    const chainId = `group:${groupId}`;
    const [members, cycles, broken, events] = await Promise.all([
      this.db.query<{ user_id: string; full_name: string; phone: string; role: string; status: string; turn_order: number | null }>(
        `SELECT u.id AS user_id, u.full_name, u.phone, m.role, m.status, m.turn_order
         FROM memberships m JOIN users u ON u.id = m.user_id WHERE m.group_id = $1
         ORDER BY m.turn_order NULLS LAST, m.joined_at`,
        [groupId],
      ),
      this.db.query<{ cycle_number: number; due_date: string; status: string; beneficiary: string; confirmed: number; expected: number }>(
        `SELECT c.cycle_number, c.due_date::text AS due_date, c.status, u.full_name AS beneficiary,
                (SELECT count(*)::int FROM contributions k WHERE k.cycle_id = c.id AND k.status = 'confirmed') AS confirmed,
                (SELECT count(*)::int - 1 FROM memberships x WHERE x.group_id = c.group_id AND x.status = 'active') AS expected
         FROM cycles c JOIN memberships m ON m.id = c.beneficiary_membership_id JOIN users u ON u.id = m.user_id
         WHERE c.group_id = $1 ORDER BY c.cycle_number`,
        [groupId],
      ),
      this.db.query<{ broken: string | null }>('SELECT audit_verify_chain($1) AS broken', [chainId]),
      this.recentEvents(this.db, chainId, 50),
    ]);
    const r = g.rows[0];
    return {
      id: r.id,
      name: r.name,
      status: r.status,
      currency: r.currency,
      contributionAmountMinor: Number(r.amount),
      frequency: r.frequency,
      startDate: r.start_date,
      turnOrderMode: r.turn_order_mode,
      drawSeed: r.draw_seed,
      suspendedReason: r.suspended_reason,
      createdAt: iso(r.created_at),
      members: members.rows.map((m) => ({
        userId: m.user_id,
        fullName: m.full_name,
        phone: this.phone(staff, m.phone),
        role: m.role,
        status: m.status,
        turnOrder: m.turn_order,
      })),
      cycles: cycles.rows.map((c) => ({
        cycleNumber: c.cycle_number,
        dueDate: c.due_date,
        status: c.status,
        beneficiary: c.beneficiary,
        confirmed: c.confirmed,
        expected: c.expected,
      })),
      chain: { chainId, intact: broken.rows[0].broken === null, firstInvalidSeq: broken.rows[0].broken },
      events,
    };
  }

  /**
   * Suspendre : plus de déclaration ni de rappel tant que la suspension dure (fraude, conflit grave).
   * Inscrit dans le journal du groupe, avec le motif.
   */
  async setGroupSuspended(staff: StaffMember, groupId: string, suspend: boolean, reason: string) {
    if (suspend && reason.trim().length < 5) throw new BadRequestException('Indiquez le motif de la suspension.');
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rows } = await q.query<{ status: string; before: string | null }>(
        'SELECT status, status_before_suspension AS before FROM groups WHERE id = $1 FOR UPDATE',
        [groupId],
      );
      const g = rows[0];
      if (!g) throw new NotFoundException('Groupe introuvable.');
      if (suspend) {
        if (g.status !== 'active' && g.status !== 'draft') {
          throw new ConflictException('Seule une tontine en préparation ou en cours peut être suspendue.');
        }
        await q.query(
          `UPDATE groups SET status = 'suspended', status_before_suspension = status, suspended_reason = $2 WHERE id = $1`,
          [groupId, reason.trim()],
        );
      } else {
        if (g.status !== 'suspended') throw new ConflictException("Cette tontine n'est pas suspendue.");
        await q.query(
          `UPDATE groups SET status = coalesce(status_before_suspension, 'active'), status_before_suspension = NULL,
                  suspended_reason = NULL WHERE id = $1`,
          [groupId],
        );
      }
      await appendAudit(q, {
        groupId,
        actor: { type: 'staff', id: staff.id },
        action: suspend ? 'staff.group_suspended' : 'staff.group_reactivated',
        payload: { group_id: groupId, reason: reason.trim() || null },
      });
      const after = await q.query<{ status: string }>('SELECT status FROM groups WHERE id = $1', [groupId]);
      return { status: after.rows[0].status };
    });
  }

  // ---------- Litiges ----------

  async disputes(staff: StaffMember, status: string) {
    const { rows } = await this.db.query<{
      id: string;
      status: string;
      reason: string;
      resolution_note: string | null;
      opened_at: Date;
      resolved_at: Date | null;
      contribution_id: string;
      contribution_status: string;
      amount: string;
      currency: string;
      method: string;
      tx_reference: string | null;
      declared_at: Date;
      group_id: string;
      group_name: string;
      cycle_number: number;
      payer: string;
      payer_phone: string;
      receiver: string;
      receiver_phone: string;
      opened_by: string;
    }>(
      `SELECT d.id, d.status, d.reason, d.resolution_note, d.opened_at, d.resolved_at,
              k.id AS contribution_id, k.status AS contribution_status, k.amount_minor AS amount, g.currency,
              k.method, k.tx_reference, k.declared_at, g.id AS group_id, g.name AS group_name, c.cycle_number,
              pu.full_name AS payer, pu.phone AS payer_phone, ru.full_name AS receiver, ru.phone AS receiver_phone,
              ou.full_name AS opened_by
       FROM disputes d
       JOIN contributions k ON k.id = d.contribution_id
       JOIN groups g ON g.id = k.group_id
       JOIN cycles c ON c.id = k.cycle_id
       JOIN memberships pm ON pm.id = k.payer_membership_id JOIN users pu ON pu.id = pm.user_id
       JOIN memberships rm ON rm.id = k.receiver_membership_id JOIN users ru ON ru.id = rm.user_id
       JOIN memberships om ON om.id = d.opened_by JOIN users ou ON ou.id = om.user_id
       WHERE ($1 = '' OR d.status::text = $1)
       ORDER BY d.opened_at DESC LIMIT 100`,
      [status],
    );
    return rows.map((r) => ({
      id: r.id,
      status: r.status,
      reason: r.reason,
      resolutionNote: r.resolution_note,
      openedAt: iso(r.opened_at),
      resolvedAt: iso(r.resolved_at),
      openedBy: r.opened_by,
      contribution: {
        id: r.contribution_id,
        status: r.contribution_status,
        amountMinor: Number(r.amount),
        currency: r.currency,
        method: r.method,
        txReference: r.tx_reference,
        declaredAt: iso(r.declared_at),
      },
      group: { id: r.group_id, name: r.group_name, cycleNumber: r.cycle_number },
      payer: { fullName: r.payer, phone: this.phone(staff, r.payer_phone) },
      receiver: { fullName: r.receiver, phone: this.phone(staff, r.receiver_phone) },
    }));
  }

  /**
   * Décision de l'équipe sur un litige ouvert (motif obligatoire, inscrit dans le journal du groupe) :
   *   reject : la déclaration est rejetée ; le payeur peut en faire une nouvelle (vrai ID de transaction) ;
   *   note   : avis consultatif ajouté au litige, qui reste ouvert (les parties s'accordent).
   * Confirmer un paiement reste réservé au bénéficiaire : l'équipe ne voit pas l'argent.
   */
  async decideDispute(staff: StaffMember, disputeId: string, decision: 'reject' | 'note', note: string) {
    if (note.trim().length < 5) throw new BadRequestException('Expliquez la décision (au moins quelques mots).');
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rows } = await q.query<{ status: string; contribution_id: string; group_id: string; contribution_status: string }>(
        `SELECT d.status, d.contribution_id, k.group_id, k.status AS contribution_status
         FROM disputes d JOIN contributions k ON k.id = d.contribution_id WHERE d.id = $1 FOR UPDATE OF d`,
        [disputeId],
      );
      const d = rows[0];
      if (!d) throw new NotFoundException('Litige introuvable.');
      if (d.status !== 'open') throw new ConflictException('Ce litige est déjà clos.');
      if (decision === 'reject') {
        if (d.contribution_status === 'confirmed') {
          throw new ConflictException('Le bénéficiaire a déjà confirmé ce paiement : il ne peut plus être rejeté.');
        }
        await q.query(`UPDATE contributions SET status = 'rejected' WHERE id = $1`, [d.contribution_id]);
        await q.query(
          `UPDATE disputes SET status = 'resolved_rejected', resolution_note = $2, resolved_at = now(), resolved_by_staff = $3
           WHERE id = $1`,
          [disputeId, note.trim(), staff.id],
        );
      } else {
        await q.query(`UPDATE disputes SET resolution_note = $2, resolved_by_staff = $3 WHERE id = $1`, [
          disputeId,
          note.trim(),
          staff.id,
        ]);
      }
      await appendAudit(q, {
        groupId: d.group_id,
        actor: { type: 'staff', id: staff.id },
        action: decision === 'reject' ? 'staff.dispute_rejected' : 'staff.dispute_note',
        payload: { dispute_id: disputeId, contribution_id: d.contribution_id, note: note.trim() },
      });
      return { decision };
    });
  }

  // ---------- Audit ----------

  async auditEvents(chainId: string, beforeSeq: number | null, limit: number) {
    return this.recentEvents(this.db, chainId, limit, beforeSeq);
  }

  async verifyChain(chainId: string) {
    const { rows } = await this.db.query<{ broken: string | null; events: number }>(
      `SELECT audit_verify_chain($1) AS broken, (SELECT count(*)::int FROM audit_log WHERE chain_id = $1) AS events`,
      [chainId],
    );
    return { chainId, events: rows[0].events, intact: rows[0].broken === null, firstInvalidSeq: rows[0].broken };
  }

  /** Les actions de l'équipe, toutes chaînes confondues. */
  async staffActions(limit: number) {
    const { rows } = await this.db.query<{
      chain_id: string;
      seq: string;
      action: string;
      payload: string;
      created_at: Date;
      staff_name: string | null;
      staff_email: string | null;
    }>(
      `SELECT a.chain_id, a.seq, a.action, a.payload, a.created_at, s.full_name AS staff_name, s.email AS staff_email
       FROM audit_log a LEFT JOIN staff s ON s.id = a.actor_id
       WHERE a.actor_type = 'staff' ORDER BY a.created_at DESC, a.id DESC LIMIT $1`,
      [limit],
    );
    return rows.map((r) => ({
      chainId: r.chain_id,
      seq: Number(r.seq),
      action: r.action,
      payload: r.payload,
      createdAt: iso(r.created_at),
      staff: r.staff_name ? `${r.staff_name} (${r.staff_email})` : null,
    }));
  }

  private async recentEvents(q: Queryable, chainId: string, limit: number, beforeSeq: number | null = null) {
    const { rows } = await q.query<{
      seq: string;
      action: string;
      actor_type: string;
      actor_name: string | null;
      payload: string;
      hash: string;
      created_at: Date;
    }>(
      `SELECT a.seq, a.action, a.actor_type, a.payload, a.hash, a.created_at,
              CASE a.actor_type WHEN 'user' THEN u.full_name WHEN 'staff' THEN 'Équipe : ' || s.full_name END AS actor_name
       FROM audit_log a
       LEFT JOIN users u ON a.actor_type = 'user' AND u.id = a.actor_id
       LEFT JOIN staff s ON a.actor_type = 'staff' AND s.id = a.actor_id
       WHERE a.chain_id = $1 AND ($2::bigint IS NULL OR a.seq < $2)
       ORDER BY a.seq DESC LIMIT $3`,
      [chainId, beforeSeq, Math.min(limit, 200)],
    );
    return rows.map((r) => ({
      seq: Number(r.seq),
      action: r.action,
      actorType: r.actor_type,
      actorName: r.actor_name,
      payload: r.payload,
      hash: r.hash,
      createdAt: iso(r.created_at),
    }));
  }
}
