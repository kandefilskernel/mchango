import {
  BadRequestException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { StaffMember } from '../admin/staff-auth.service.js';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { activeMembership } from '../groups/membership.js';
import { appendAudit, Db } from '../infra/database.js';
import { AI_ANALYST, AnalystUnavailable, type Analyst } from './analyst.js';
import { groupDataset, ruleSignals, scrub, type Signal } from './signals.js';

/** Avis qu'un membre peut laisser par jour (évite le spam ; un vrai problème passe par le support). */
export const MAX_FEEDBACK_PER_DAY = 5;
const FEEDBACK_WINDOW_DAYS = 30;
const FEEDBACK_MAX_ITEMS = 300;

const iso = (d: Date | null | undefined) => d?.toISOString() ?? null;

interface ReviewRow {
  id: string;
  kind: 'group' | 'feedback';
  group_id: string | null;
  group_name: string | null;
  requested_by_name: string;
  model: string;
  signals: { rules?: Signal[]; codes?: Record<string, string>; refs?: Record<string, string> };
  result: unknown;
  error: string | null;
  input_tokens: number | null;
  output_tokens: number | null;
  created_at: Date;
}

@Injectable()
export class AiService {
  constructor(
    private readonly db: Db,
    @Inject(AI_ANALYST) private readonly analyst: Analyst,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  // ---------- Membres : donner son avis ----------

  async submitFeedback(
    actor: { userId: string; deviceId: string },
    input: { groupId?: string; rating?: number; body: string },
  ) {
    const body = input.body.trim();
    if (body.length < 3) throw new BadRequestException('Écrivez votre avis.');
    return this.db.transaction({ type: 'user', id: actor.userId, deviceId: actor.deviceId }, async (q) => {
      if (input.groupId && !(await activeMembership(q, actor.userId, input.groupId))) {
        throw new ForbiddenException("Vous n'êtes pas membre de cette tontine.");
      }
      // Verrou par utilisateur : deux envois simultanés ne dépassent pas la limite
      await q.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`feedback:${actor.userId}`]);
      const { rows: count } = await q.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM member_feedback WHERE user_id = $1 AND created_at > now() - interval '1 day'`,
        [actor.userId],
      );
      if (count[0].n >= MAX_FEEDBACK_PER_DAY) {
        throw new HttpException("Vous avez déjà envoyé plusieurs avis aujourd'hui. Merci, réessayez demain.", HttpStatus.TOO_MANY_REQUESTS);
      }
      const { rows } = await q.query<{ id: string; created_at: Date }>(
        `INSERT INTO member_feedback (user_id, group_id, rating, body) VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
        [actor.userId, input.groupId ?? null, input.rating ?? null, body],
      );
      return { id: rows[0].id, createdAt: iso(rows[0].created_at) };
    });
  }

  // ---------- Équipe : analyses ----------

  status() {
    return { enabled: this.analyst.enabled, model: this.analyst.model, perDay: this.config.AI_REVIEWS_PER_DAY };
  }

  /**
   * Analyse une tontine : règles automatiques (toujours) + agent IA (si configuré), sur des données
   * pseudonymisées. Le résultat est un avis pour l'équipe, jamais une décision : rien n'est bloqué.
   */
  async reviewGroup(staff: StaffMember, groupId: string) {
    const exists = await this.db.query('SELECT 1 FROM groups WHERE id = $1', [groupId]);
    if (exists.rowCount !== 1) throw new NotFoundException('Tontine introuvable.');
    const { dataset, pseudonyms } = await groupDataset(this.db, groupId);
    const rules = ruleSignals(dataset);
    const ai = await this.callAnalyst(() => this.analyst.reviewGroup(dataset, rules));
    const id = await this.store(staff, 'group', groupId, { rules, codes: pseudonyms.codes }, ai);
    return this.review(id);
  }

  /** Synthèse des avis des 30 derniers jours (références F1, F2… à la place des auteurs). */
  async reviewFeedback(staff: StaffMember) {
    const { rows } = await this.db.query<{ id: string; rating: number | null; body: string; full_name: string }>(
      `SELECT f.id, f.rating, f.body, u.full_name FROM member_feedback f JOIN users u ON u.id = f.user_id
       WHERE f.created_at > now() - make_interval(days => $1) ORDER BY f.created_at DESC LIMIT $2`,
      [FEEDBACK_WINDOW_DAYS, FEEDBACK_MAX_ITEMS],
    );
    if (rows.length === 0) throw new BadRequestException('Aucun avis ces 30 derniers jours.');
    const refs: Record<string, string> = {};
    const items = rows.map((r, i) => {
      const ref = `F${i + 1}`;
      refs[ref] = r.id;
      return { ref, rating: r.rating, text: scrub(r.body, new Map([[r.full_name, 'le membre']])) };
    });
    const ai = await this.callAnalyst(() => this.analyst.reviewFeedback(items));
    const id = await this.store(staff, 'feedback', null, { refs }, ai);
    return this.review(id);
  }

  async reviews(groupId?: string) {
    const { rows } = await this.db.query<ReviewRow>(
      `${REVIEW_SELECT} WHERE ($1::uuid IS NULL OR r.group_id = $1) ORDER BY r.created_at DESC LIMIT 50`,
      [groupId ?? null],
    );
    return rows.map((r) => ({
      id: r.id,
      kind: r.kind,
      groupId: r.group_id,
      groupName: r.group_name,
      requestedBy: r.requested_by_name,
      riskLevel: (r.result as { risk_level?: string } | null)?.risk_level ?? null,
      signals: r.signals.rules?.length ?? 0,
      error: r.error,
      createdAt: iso(r.created_at),
    }));
  }

  /** Une analyse, avec les codes M1, M2… et F1, F2… remis en clair pour l'équipe. */
  async review(id: string) {
    const { rows } = await this.db.query<ReviewRow>(`${REVIEW_SELECT} WHERE r.id = $1`, [id]);
    const r = rows[0];
    if (!r) throw new NotFoundException('Analyse introuvable.');
    const members: Record<string, { membershipId: string; userId: string; fullName: string }> = {};
    const codes = r.signals.codes ?? {};
    if (Object.keys(codes).length > 0) {
      const { rows: people } = await this.db.query<{ id: string; user_id: string; full_name: string }>(
        'SELECT m.id, m.user_id, u.full_name FROM memberships m JOIN users u ON u.id = m.user_id WHERE m.id = ANY($1::uuid[])',
        [Object.values(codes)],
      );
      const byId = new Map(people.map((p) => [p.id, p]));
      for (const [code, membershipId] of Object.entries(codes)) {
        const p = byId.get(membershipId);
        if (p) members[code] = { membershipId, userId: p.user_id, fullName: p.full_name };
      }
    }
    const feedback: Record<string, { id: string; userId: string; fullName: string; body: string }> = {};
    const refs = r.signals.refs ?? {};
    if (Object.keys(refs).length > 0) {
      const { rows: items } = await this.db.query<{ id: string; user_id: string; full_name: string; body: string }>(
        'SELECT f.id, f.user_id, u.full_name, f.body FROM member_feedback f JOIN users u ON u.id = f.user_id WHERE f.id = ANY($1::uuid[])',
        [Object.values(refs)],
      );
      const byId = new Map(items.map((f) => [f.id, f]));
      for (const [ref, feedbackId] of Object.entries(refs)) {
        const f = byId.get(feedbackId);
        if (f) feedback[ref] = { id: f.id, userId: f.user_id, fullName: f.full_name, body: f.body };
      }
    }
    return {
      id: r.id,
      kind: r.kind,
      groupId: r.group_id,
      groupName: r.group_name,
      requestedBy: r.requested_by_name,
      model: r.model,
      rules: r.signals.rules ?? [],
      result: r.result,
      error: r.error,
      usage: { inputTokens: r.input_tokens, outputTokens: r.output_tokens },
      members,
      feedback,
      createdAt: iso(r.created_at),
    };
  }

  async feedbackList(groupId?: string) {
    const { rows } = await this.db.query<{
      id: string;
      user_id: string;
      full_name: string;
      group_id: string | null;
      group_name: string | null;
      rating: number | null;
      body: string;
      created_at: Date;
    }>(
      `SELECT f.id, f.user_id, u.full_name, f.group_id, g.name AS group_name, f.rating, f.body, f.created_at
       FROM member_feedback f JOIN users u ON u.id = f.user_id LEFT JOIN groups g ON g.id = f.group_id
       WHERE ($1::uuid IS NULL OR f.group_id = $1) ORDER BY f.created_at DESC LIMIT 200`,
      [groupId ?? null],
    );
    return rows.map((f) => ({
      id: f.id,
      userId: f.user_id,
      fullName: f.full_name,
      groupId: f.group_id,
      groupName: f.group_name,
      rating: f.rating,
      body: f.body,
      createdAt: iso(f.created_at),
    }));
  }

  // ---------- Interne ----------

  private async callAnalyst<T>(run: () => Promise<{ model: string; result: T; inputTokens: number; outputTokens: number }>) {
    if (!this.analyst.enabled) {
      return { model: 'règles', result: null, error: "Agent IA non configuré : seules les règles automatiques ont tourné.", inputTokens: null, outputTokens: null };
    }
    const { rows } = await this.db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM ai_reviews WHERE result IS NOT NULL AND created_at > now() - interval '1 day'`,
    );
    if (rows[0].n >= this.config.AI_REVIEWS_PER_DAY) {
      return { model: 'règles', result: null, error: `Plafond de ${this.config.AI_REVIEWS_PER_DAY} analyses IA par jour atteint : seules les règles ont tourné.`, inputTokens: null, outputTokens: null };
    }
    try {
      const ai = await run();
      return { ...ai, error: null };
    } catch (error) {
      if (!(error instanceof AnalystUnavailable)) throw error;
      return { model: this.analyst.model, result: null, error: error.message, inputTokens: null, outputTokens: null };
    }
  }

  private store(
    staff: StaffMember,
    kind: 'group' | 'feedback',
    groupId: string | null,
    signals: object,
    ai: { model: string; result: unknown; error: string | null; inputTokens: number | null; outputTokens: number | null },
  ) {
    return this.db.transaction({ type: 'staff', id: staff.id }, async (q) => {
      const { rows } = await q.query<{ id: string }>(
        `INSERT INTO ai_reviews (kind, group_id, requested_by, model, signals, result, error, input_tokens, output_tokens)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id`,
        [kind, groupId, staff.id, ai.model, JSON.stringify(signals), ai.result === null ? null : JSON.stringify(ai.result), ai.error, ai.inputTokens, ai.outputTokens],
      );
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: staff.id },
        action: 'staff.ai_review',
        payload: { review_id: rows[0].id, kind, group_id: groupId, ai: ai.result !== null },
      });
      return rows[0].id;
    });
  }
}

const REVIEW_SELECT = `SELECT r.id, r.kind, r.group_id, g.name AS group_name, s.full_name AS requested_by_name, r.model,
       r.signals, r.result, r.error, r.input_tokens, r.output_tokens, r.created_at
  FROM ai_reviews r JOIN staff s ON s.id = r.requested_by LEFT JOIN groups g ON g.id = r.group_id`;
