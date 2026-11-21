import {
  ConflictException,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash, randomInt } from 'node:crypto';
import type { Redis } from 'ioredis';
import { Db, isUniqueViolation, type Actor } from '../infra/database.js';
import { REDIS } from '../infra/redis.js';

type UserActor = Actor & { id: string };

export const ATTESTATION_VERSION = 'mchango-attestation-v1';
/** Sans 0/O, 1/I/L ni U, comme les codes d'invitation : se dicte au téléphone sans erreur. */
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const CODE_LENGTH = 10; // 30^10 ≈ 5,9 × 10^14, avec limitation des consultations
const ISSUED_PER_DAY = 5;
const VERIFY_PER_HOUR = 60;

export const ATTESTATION_NOTICE =
  "Relevé des cotisations déclarées par ce membre et confirmées par leurs bénéficiaires dans Mchango. " +
  "Ce n'est ni un score de crédit ni une garantie : Mchango ne détient, ne prête ni ne garantit aucun argent.";

export function generateAttestationCode(): string {
  return Array.from({ length: CODE_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join('');
}

/** Forme canonique d'un code saisi (« K7MPQ-2XWAB » → « K7MPQ2XWAB »), ou null. */
export function normalizeAttestationCode(input: string): string | null {
  const code = input.toUpperCase().replace(/[\s-]/g, '');
  return code.length === CODE_LENGTH && code.split('').every((c) => ALPHABET.includes(c)) ? code : null;
}

/** « +243970000012 » → « +24397*****12 » : assez pour reconnaître le titulaire, pas pour l'appeler. */
export function maskPhone(phone: string): string {
  return phone.length <= 8 ? phone : `${phone.slice(0, 6)}${'*'.repeat(phone.length - 8)}${phone.slice(-2)}`;
}

export interface AttestationStats {
  memberSince: string;
  tontines: { joined: number; completed: number; active: number };
  contributions: { confirmed: number; onTime: number; late: number; rejected: number; disputed: number };
  /** Paiements confirmés faits à temps, en % arrondi ; null sans aucun paiement confirmé. */
  onTimeRatePercent: number | null;
  turnsReceived: number;
  firstConfirmedAt: string | null;
  lastConfirmedAt: string | null;
  amounts: { currency: string; paidMinor: number }[];
}

interface AttestationRow {
  id: string;
  code: string;
  content: string;
  content_hash: string;
  issued_at: Date;
  expires_at: Date;
  revoked_at: Date | null;
}

function statusOf(r: AttestationRow): 'valid' | 'expired' | 'revoked' {
  if (r.revoked_at) return 'revoked';
  return r.expires_at.getTime() <= Date.now() ? 'expired' : 'valid';
}

function toAttestation(r: AttestationRow) {
  return {
    id: r.id,
    code: r.code,
    status: statusOf(r),
    content: JSON.parse(r.content) as object,
    contentHash: r.content_hash,
    // Contenu du QR code : le code et l'empreinte du contenu (spec/attestations.md)
    qrPayload: `MCHANGO-ATT1|${r.code}|${r.content_hash}`,
    issuedAt: r.issued_at.toISOString(),
    expiresAt: r.expires_at.toISOString(),
    revokedAt: r.revoked_at?.toISOString() ?? null,
  };
}

/**
 * Attestation de régularité (spec/attestations.md) : le membre fige un relevé de ses cotisations
 * et le montre à qui il veut (IMF, coopec, bailleur) avec un code. Des faits constatés dans le
 * journal, pas une note : à chacun d'en tirer ses conclusions.
 */
@Injectable()
export class AttestationsService {
  constructor(
    private readonly db: Db,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  /** Les chiffres qui entreraient dans une attestation émise maintenant. */
  async stats(userId: string): Promise<AttestationStats> {
    const { rows } = await this.db.query<{
      member_since: string;
      joined: number;
      completed: number;
      active: number;
      confirmed: number;
      on_time: number;
      late: number;
      rejected: number;
      disputed: number;
      turns_received: number;
      first_confirmed: Date | null;
      last_confirmed: Date | null;
    }>(
      `WITH mine AS (
         SELECT m.id, m.status AS m_status, g.status AS g_status
         FROM memberships m JOIN groups g ON g.id = m.group_id
         WHERE m.user_id = $1 AND g.status <> 'draft'
       ), paid AS (
         SELECT k.* FROM contributions k WHERE k.payer_membership_id IN (SELECT id FROM mine)
       )
       SELECT (SELECT (created_at AT TIME ZONE 'Africa/Lubumbashi')::date::text FROM users WHERE id = $1) AS member_since,
              (SELECT count(*)::int FROM mine) AS joined,
              (SELECT count(*)::int FROM mine WHERE g_status = 'closed' AND m_status = 'active') AS completed,
              (SELECT count(*)::int FROM mine WHERE g_status = 'active' AND m_status = 'active') AS active,
              (SELECT count(*)::int FROM paid WHERE status = 'confirmed') AS confirmed,
              (SELECT count(*)::int FROM paid WHERE status = 'confirmed' AND NOT is_late) AS on_time,
              (SELECT count(*)::int FROM paid WHERE status = 'confirmed' AND is_late) AS late,
              (SELECT count(*)::int FROM paid WHERE status = 'rejected') AS rejected,
              (SELECT count(*)::int FROM paid WHERE status = 'disputed') AS disputed,
              (SELECT count(*)::int FROM cycles c
                WHERE c.beneficiary_membership_id IN (SELECT id FROM mine) AND c.status = 'completed') AS turns_received,
              (SELECT min(declared_at) FROM paid WHERE status = 'confirmed') AS first_confirmed,
              (SELECT max(declared_at) FROM paid WHERE status = 'confirmed') AS last_confirmed`,
      [userId],
    );
    const amounts = await this.db.query<{ currency: string; paid: string }>(
      `SELECT g.currency, sum(k.amount_minor) AS paid
       FROM contributions k JOIN memberships m ON m.id = k.payer_membership_id JOIN groups g ON g.id = k.group_id
       WHERE m.user_id = $1 AND k.status = 'confirmed'
       GROUP BY g.currency ORDER BY g.currency`,
      [userId],
    );
    const r = rows[0];
    return {
      memberSince: r.member_since,
      tontines: { joined: r.joined, completed: r.completed, active: r.active },
      contributions: {
        confirmed: r.confirmed,
        onTime: r.on_time,
        late: r.late,
        rejected: r.rejected,
        disputed: r.disputed,
      },
      onTimeRatePercent: r.confirmed === 0 ? null : Math.round((100 * r.on_time) / r.confirmed),
      turnsReceived: r.turns_received,
      firstConfirmedAt: r.first_confirmed?.toISOString() ?? null,
      lastConfirmedAt: r.last_confirmed?.toISOString() ?? null,
      amounts: amounts.rows.map((a) => ({ currency: a.currency, paidMinor: Number(a.paid) })),
    };
  }

  /** Émet une attestation : contenu figé, empreinte, code de vérification. */
  async issue(actor: UserActor, input: { includeAmounts: boolean; validDays: number }) {
    const recent = await this.db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM attestations WHERE user_id = $1 AND issued_at > now() - interval '1 day'`,
      [actor.id],
    );
    if (recent.rows[0].n >= ISSUED_PER_DAY) {
      throw new HttpException(
        `Au plus ${ISSUED_PER_DAY} attestations par jour. Réutilisez une attestation déjà émise.`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const stats = await this.stats(actor.id);
    if (stats.contributions.confirmed === 0) {
      throw new ConflictException("Pas encore d'attestation possible : aucun paiement confirmé pour le moment.");
    }
    const user = await this.db.query<{ full_name: string; phone: string }>(
      'SELECT full_name, phone FROM users WHERE id = $1',
      [actor.id],
    );
    const issuedAt = new Date(Math.floor(Date.now() / 1000) * 1000);
    const expiresAt = new Date(issuedAt.getTime() + input.validDays * 86_400_000);
    // Ordre des clés fixe : le texte stocké est celui qui est haché, octet pour octet
    const content = JSON.stringify({
      version: ATTESTATION_VERSION,
      holder: { fullName: user.rows[0].full_name, phone: maskPhone(user.rows[0].phone) },
      memberSince: stats.memberSince,
      tontines: stats.tontines,
      contributions: stats.contributions,
      onTimeRatePercent: stats.onTimeRatePercent,
      turnsReceived: stats.turnsReceived,
      firstConfirmedAt: stats.firstConfirmedAt,
      lastConfirmedAt: stats.lastConfirmedAt,
      amounts: input.includeAmounts ? stats.amounts : null,
      issuedAt: issuedAt.toISOString(),
      expiresAt: expiresAt.toISOString(),
      notice: ATTESTATION_NOTICE,
    });
    const hash = createHash('sha256').update(content, 'utf8').digest('hex');

    for (let attempt = 0; ; attempt++) {
      try {
        return await this.db.transaction(actor, async (q) => {
          const { rows } = await q.query<AttestationRow>(
            `INSERT INTO attestations (user_id, code, content, content_hash, issued_at, expires_at)
             VALUES ($1, $2, $3, $4, $5, $6)
             RETURNING id, code, content, content_hash, issued_at, expires_at, revoked_at`,
            [actor.id, generateAttestationCode(), content, hash, issuedAt, expiresAt],
          );
          return toAttestation(rows[0]);
        });
      } catch (e) {
        // Code déjà pris (très improbable) : on en tire un autre
        if (attempt < 3 && isUniqueViolation(e)) continue;
        throw e;
      }
    }
  }

  async listMine(userId: string) {
    const { rows } = await this.db.query<AttestationRow>(
      `SELECT id, code, content, content_hash, issued_at, expires_at, revoked_at
       FROM attestations WHERE user_id = $1 ORDER BY issued_at DESC LIMIT 20`,
      [userId],
    );
    return rows.map(toAttestation);
  }

  /** Le titulaire retire une attestation : le code ne montre plus que « retirée ». */
  async revoke(actor: UserActor, id: string) {
    return this.db.transaction(actor, async (q) => {
      const { rows } = await q.query<AttestationRow>(
        `UPDATE attestations SET revoked_at = now()
         WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL
         RETURNING id, code, content, content_hash, issued_at, expires_at, revoked_at`,
        [id, actor.id],
      );
      if (!rows[0]) throw new NotFoundException('Attestation introuvable ou déjà retirée.');
      return toAttestation(rows[0]);
    });
  }

  /**
   * Vérification par un tiers, sans compte. Une attestation retirée ne montre plus son contenu ;
   * une attestation expirée le montre, marquée « expirée ».
   */
  async verify(rawCode: string, ip: string) {
    const key = `rl:attestation:ip:${ip}`;
    const count = await this.redis.incr(key);
    if (count === 1) await this.redis.expire(key, 3600);
    if (count > VERIFY_PER_HOUR) {
      throw new HttpException('Trop de vérifications. Réessayez dans une heure.', HttpStatus.TOO_MANY_REQUESTS);
    }
    const code = normalizeAttestationCode(rawCode);
    const { rows } = await this.db.query<AttestationRow>(
      `SELECT id, code, content, content_hash, issued_at, expires_at, revoked_at FROM attestations WHERE code = $1`,
      [code ?? ''],
    );
    if (!rows[0]) throw new NotFoundException('Attestation inconnue. Vérifiez le code.');
    const a = toAttestation(rows[0]);
    return {
      code: a.code,
      status: a.status,
      content: a.status === 'revoked' ? null : a.content,
      contentHash: a.status === 'revoked' ? null : a.contentHash,
      issuedAt: a.issuedAt,
      expiresAt: a.expiresAt,
    };
  }
}
