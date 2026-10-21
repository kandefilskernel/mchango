import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { hash, verify } from '@node-rs/argon2';
import { randomBytes } from 'node:crypto';
import type { Redis } from 'ioredis';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { appendAudit, Db, isUniqueViolation, type Queryable } from '../infra/database.js';
import { REDIS } from '../infra/redis.js';
import { newTotpSecret, openSecret, otpauthUrl, sealSecret, verifyTotp } from './totp.js';

export const STAFF_ROLES = ['super_admin', 'support', 'compliance', 'finance', 'read_only'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export interface StaffClaims {
  typ: 'staff';
  sub: string;
  role: StaffRole;
}

export interface StaffMember {
  id: string;
  email: string;
  fullName: string;
  role: StaffRole;
}

/** Session de l'équipe : une journée de travail au plus. */
const STAFF_TOKEN_TTL_SECONDS = 8 * 60 * 60;
const MAX_LOGIN_FAILURES = 5;
const LOCK_SECONDS = 15 * 60;
const ARGON2 = { memoryCost: 19456, timeCost: 2, parallelism: 1 };

/** Mot de passe initial : 16 caractères sans ambiguïté, à changer à la première connexion. */
function temporaryPassword(): string {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = randomBytes(16);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

export function passwordWeakness(password: string): string | null {
  if (password.length < 12) return 'Le mot de passe doit faire au moins 12 caractères.';
  if (!/[a-z]/i.test(password) || !/\d/.test(password)) return 'Le mot de passe doit contenir des lettres et des chiffres.';
  return null;
}

/**
 * Comptes de l'équipe : e-mail + mot de passe (argon2id) + code à 6 chiffres d'une application
 * d'authentification, toujours. Pas de connexion sans les trois.
 */
@Injectable()
export class StaffAuthService {
  constructor(
    private readonly db: Db,
    private readonly jwt: JwtService,
    @Inject(REDIS) private readonly redis: Redis,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  async login(emailInput: string, password: string, code: string) {
    const email = emailInput.trim().toLowerCase();
    const failKey = `staff:login-fail:${email}`;
    if (Number(await this.redis.get(failKey)) >= MAX_LOGIN_FAILURES) {
      throw new HttpException(
        'Trop de tentatives. Compte bloqué 15 minutes : réessayez plus tard.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const { rows } = await this.db.query<{
      id: string;
      email: string;
      full_name: string;
      role: StaffRole;
      password_hash: string;
      totp_secret_enc: string | null;
      is_active: boolean;
      must_change: boolean;
    }>(
      `SELECT id, email, full_name, role, password_hash, totp_secret_enc, is_active,
              password_changed_at IS NULL AS must_change
       FROM staff WHERE lower(email) = $1`,
      [email],
    );
    const s = rows[0];
    // Développement seulement (refusé en production par loadConfig) : « 000000 » remplace le code
    const devBypass = this.config.STAFF_2FA_DEV_BYPASS === '1' && code === '000000';
    const ok =
      s?.is_active &&
      s.totp_secret_enc &&
      (await verify(s.password_hash, password)) &&
      (devBypass || verifyTotp(openSecret(s.totp_secret_enc, this.config.STAFF_SECRET_KEY), code));
    if (!ok) {
      const fails = await this.redis.incr(failKey);
      if (fails === 1) await this.redis.expire(failKey, LOCK_SECONDS);
      // Même message dans tous les cas : ne pas révéler si l'e-mail existe
      throw new UnauthorizedException('E-mail, mot de passe ou code incorrect.');
    }
    await this.redis.del(failKey);
    await this.db.transaction({ type: 'staff', id: s.id }, async (q) => {
      await q.query(
        `UPDATE staff SET last_login_at = now(), totp_enabled_at = coalesce(totp_enabled_at, now()) WHERE id = $1`,
        [s.id],
      );
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: s.id },
        action: 'staff.login',
        payload: { staff_id: s.id, ...(devBypass ? { two_factor: 'dev_bypass' } : {}) },
      });
    });
    const claims: StaffClaims = { typ: 'staff', sub: s.id, role: s.role };
    const token = await this.jwt.signAsync(claims, {
      secret: this.config.STAFF_JWT_SECRET,
      expiresIn: STAFF_TOKEN_TTL_SECONDS,
      algorithm: 'HS256',
    });
    return {
      token,
      expiresIn: STAFF_TOKEN_TTL_SECONDS,
      mustChangePassword: s.must_change,
      staff: { id: s.id, email: s.email, fullName: s.full_name, role: s.role },
    };
  }

  /** Vérifie le jeton ET que le compte est toujours actif (désactivation effective immédiatement). */
  async authenticate(token: string): Promise<StaffMember> {
    const claims = await this.jwt
      .verifyAsync<StaffClaims>(token, { secret: this.config.STAFF_JWT_SECRET, algorithms: ['HS256'] })
      .catch(() => null);
    if (claims?.typ !== 'staff') throw new UnauthorizedException('Session expirée. Reconnectez-vous.');
    const { rows } = await this.db.query<{ id: string; email: string; full_name: string; role: StaffRole }>(
      'SELECT id, email, full_name, role FROM staff WHERE id = $1 AND is_active',
      [claims.sub],
    );
    if (!rows[0]) throw new UnauthorizedException('Compte désactivé.');
    const r = rows[0];
    return { id: r.id, email: r.email, fullName: r.full_name, role: r.role };
  }

  /**
   * Nouveau compte d'équipe. Renvoie UNE SEULE FOIS le mot de passe provisoire et le secret 2FA
   * (à enregistrer dans l'application d'authentification de la personne).
   */
  async create(by: StaffMember | null, input: { email: string; fullName: string; role: StaffRole }) {
    const password = temporaryPassword();
    const secret = newTotpSecret();
    const email = input.email.trim().toLowerCase();
    const actor = by ? ({ type: 'staff', id: by.id } as const) : ({ type: 'system' } as const);
    const created = await this.db
      .transaction(actor, async (q) => {
        const { rows } = await q.query<{ id: string }>(
          `INSERT INTO staff (email, full_name, password_hash, role, totp_secret_enc)
           VALUES ($1, $2, $3, $4, $5) RETURNING id`,
          [email, input.fullName.trim(), await hash(password, ARGON2), input.role, sealSecret(secret, this.config.STAFF_SECRET_KEY)],
        );
        await appendAudit(q, {
          groupId: null,
          actor,
          action: 'staff.created',
          payload: { staff_id: rows[0].id, email, role: input.role },
        });
        return rows[0].id;
      })
      .catch((e: unknown) => {
        if (isUniqueViolation(e)) throw new ConflictException('Un compte existe déjà avec cet e-mail.');
        throw e;
      });
    return { id: created, email, temporaryPassword: password, totpSecret: secret, otpauthUrl: otpauthUrl(email, secret) };
  }

  /**
   * Nouveaux identifiants (mot de passe provisoire + secret 2FA) pour un compte existant :
   * téléphone perdu, identifiants jamais notés. Réservé à la ligne de commande sur le serveur
   * (accès machine = racine de confiance). Les anciens ne marchent plus ; c'est journalisé.
   */
  async resetCredentials(emailInput: string) {
    const email = emailInput.trim().toLowerCase();
    const password = temporaryPassword();
    const secret = newTotpSecret();
    await this.db.transaction({ type: 'system' }, async (q) => {
      const { rows } = await q.query<{ id: string }>(
        `UPDATE staff SET password_hash = $2, totp_secret_enc = $3, totp_enabled_at = NULL, password_changed_at = NULL
         WHERE lower(email) = $1 RETURNING id`,
        [email, await hash(password, ARGON2), sealSecret(secret, this.config.STAFF_SECRET_KEY)],
      );
      if (!rows[0]) throw new NotFoundException(`Aucun compte d'équipe pour ${email}.`);
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'system' },
        action: 'staff.credentials_reset',
        payload: { staff_id: rows[0].id },
      });
    });
    await this.redis.del(`staff:login-fail:${email}`);
    return { email, temporaryPassword: password, totpSecret: secret, otpauthUrl: otpauthUrl(email, secret) };
  }

  async list() {
    const { rows } = await this.db.query<{
      id: string;
      email: string;
      full_name: string;
      role: StaffRole;
      is_active: boolean;
      last_login_at: Date | null;
      totp_enabled_at: Date | null;
    }>('SELECT id, email, full_name, role, is_active, last_login_at, totp_enabled_at FROM staff ORDER BY created_at');
    return rows.map((r) => ({
      id: r.id,
      email: r.email,
      fullName: r.full_name,
      role: r.role,
      isActive: r.is_active,
      lastLoginAt: r.last_login_at?.toISOString() ?? null,
      twoFactorEnrolled: r.totp_enabled_at !== null,
    }));
  }

  /** Changement de rôle ou activation : journalisé (« alerte de changement de rôle »). */
  async update(by: StaffMember, staffId: string, change: { role?: StaffRole; isActive?: boolean }) {
    if (staffId === by.id) throw new BadRequestException('Vous ne pouvez pas modifier votre propre compte ici.');
    return this.db.transaction({ type: 'staff', id: by.id }, async (q) => {
      const before = await q.query<{ role: StaffRole; is_active: boolean }>(
        'SELECT role, is_active FROM staff WHERE id = $1 FOR UPDATE',
        [staffId],
      );
      if (!before.rows[0]) throw new NotFoundException('Compte introuvable.');
      const role = change.role ?? before.rows[0].role;
      const isActive = change.isActive ?? before.rows[0].is_active;
      await q.query('UPDATE staff SET role = $2, is_active = $3 WHERE id = $1', [staffId, role, isActive]);
      await this.assertSuperAdminRemains(q);
      await appendAudit(q, {
        groupId: null,
        actor: { type: 'staff', id: by.id },
        action: 'staff.updated',
        payload: { staff_id: staffId, role_before: before.rows[0].role, role, active_before: before.rows[0].is_active, active: isActive },
      });
      return { id: staffId, role, isActive };
    });
  }

  async changePassword(me: StaffMember, current: string, next: string) {
    const weakness = passwordWeakness(next);
    if (weakness) throw new BadRequestException(weakness);
    const { rows } = await this.db.query<{ password_hash: string }>('SELECT password_hash FROM staff WHERE id = $1', [me.id]);
    if (!(await verify(rows[0].password_hash, current))) throw new UnauthorizedException('Mot de passe actuel incorrect.');
    await this.db.transaction({ type: 'staff', id: me.id }, async (q) => {
      await q.query('UPDATE staff SET password_hash = $2, password_changed_at = now() WHERE id = $1', [
        me.id,
        await hash(next, ARGON2),
      ]);
      await appendAudit(q, { groupId: null, actor: { type: 'staff', id: me.id }, action: 'staff.password_changed', payload: { staff_id: me.id } });
    });
    return { ok: true };
  }

  private async assertSuperAdminRemains(q: Queryable) {
    const { rows } = await q.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM staff WHERE role = 'super_admin' AND is_active`,
    );
    if (rows[0].n === 0) throw new ConflictException('Il doit rester au moins un super administrateur actif.');
  }
}
