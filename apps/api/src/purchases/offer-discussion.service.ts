import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { createHash } from 'node:crypto';
import { Db, type Actor } from '../infra/database.js';

/** Types d'image acceptés, reconnus à leurs premiers octets (on ne croit pas l'en-tête seul). */
const SIGNATURES: [string, number[]][] = [
  ['image/jpeg', [0xff, 0xd8, 0xff]],
  ['image/png', [0x89, 0x50, 0x4e, 0x47]],
  ['image/webp', [0x52, 0x49, 0x46, 0x46]], // « RIFF » (… « WEBP » plus loin)
];
export const MAX_PHOTO_BYTES = 600_000;
const MAX_PHOTOS = 4;
const MESSAGES_PER_10_MIN = 10;

export function sniffImage(bytes: Buffer): string | null {
  for (const [type, sig] of SIGNATURES) {
    if (sig.every((b, i) => bytes[i] === b)) {
      if (type === 'image/webp' && bytes.subarray(8, 12).toString('ascii') !== 'WEBP') continue;
      return type;
    }
  }
  return null;
}

/** « Maman Neema Kabila » → « Maman Neema » : de quoi reconnaître, sans tout le nom. */
function shortName(full: string): string {
  const w = full.trim().split(/\s+/);
  return w.length > 2 ? `${w[0]} ${w[1]}` : full.trim();
}

/**
 * Voir la marchandise et en discuter (spec/achats.md) : photos d'une offre, ajoutées par la boutique
 * avant publication ; messages sous l'offre, de tout membre connecté, la boutique marquée comme telle.
 */
@Injectable()
export class OfferDiscussionService {
  constructor(private readonly db: Db) {}

  /** La boutique ajoute une photo à une offre en brouillon (au plus 4). */
  async addPhoto(actor: Actor & { id: string }, merchantId: string, memberId: string, offerId: string, bytes: Buffer) {
    if (!Buffer.isBuffer(bytes) || bytes.length === 0) {
      throw new BadRequestException('Envoyez une photo (JPEG, PNG ou WebP).');
    }
    if (bytes.length > MAX_PHOTO_BYTES) {
      throw new BadRequestException('Photo trop lourde : 600 Ko au plus. Réduisez-la avant de l’envoyer.');
    }
    const type = sniffImage(bytes);
    if (!type) throw new BadRequestException('Ce fichier n’est pas une photo JPEG, PNG ou WebP.');
    const sha256 = createHash('sha256').update(bytes).digest('hex');

    return this.db.transaction(actor, async (q) => {
      const offer = await q.query<{ status: string }>(
        'SELECT status FROM offers WHERE id = $1 AND merchant_id = $2 FOR UPDATE',
        [offerId, merchantId],
      );
      if (!offer.rows[0]) throw new NotFoundException('Offre introuvable.');
      if (offer.rows[0].status !== 'draft') throw new ConflictException('Offre publiée : ses photos ne changent plus.');
      const count = await q.query<{ n: number }>('SELECT count(*)::int AS n FROM offer_photos WHERE offer_id = $1', [offerId]);
      if (count.rows[0].n >= MAX_PHOTOS) throw new ConflictException(`${MAX_PHOTOS} photos au plus par offre.`);
      const position = count.rows[0].n + 1;
      await q.query(
        `INSERT INTO offer_photos (offer_id, position, content_type, bytes, sha256, added_by_member_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [offerId, position, type, bytes, sha256, memberId],
      );
      // L'image est trop lourde pour le journal : on y inscrit son empreinte, dans la chaîne de l'offre
      await q.query(
        `INSERT INTO audit_log (offer_id, actor_type, actor_id, device_id, action, payload)
         VALUES ($1, 'user', $2, $3, 'offer_photos.insert', $4)`,
        [offerId, actor.id, actor.deviceId ?? null, JSON.stringify({ offer_id: offerId, position, content_type: type, sha256, bytes: bytes.length })],
      );
      return { position, url: `/offers/${offerId}/photos/${position}`, sha256 };
    });
  }

  /** Une photo, servie telle quelle (pas de compte nécessaire, comme l'offre). */
  async photo(offerId: string, position: number) {
    const { rows } = await this.db.query<{ bytes: Buffer; content_type: string; sha256: string }>(
      `SELECT ph.bytes, ph.content_type, ph.sha256 FROM offer_photos ph
       WHERE ph.offer_id = $1 AND ph.position = $2`,
      [offerId, position],
    );
    if (!rows[0]) throw new NotFoundException('Photo introuvable.');
    return rows[0];
  }

  /** La discussion sous une offre, la plus ancienne en premier (100 derniers messages). */
  async messages(userId: string, offerId: string) {
    const { rows } = await this.db.query<{
      id: string;
      author_user_id: string;
      full_name: string;
      merchant_name: string | null;
      body: string;
      created_at: Date;
    }>(
      `SELECT * FROM (
         SELECT om.id, om.author_user_id, u.full_name, m.name AS merchant_name, om.body, om.created_at
         FROM offer_messages om
         JOIN offers o ON o.id = om.offer_id
         JOIN users u ON u.id = om.author_user_id
         LEFT JOIN merchants m ON om.merchant_member_id IS NOT NULL AND m.id = o.merchant_id
         WHERE om.offer_id = $1 AND om.hidden_at IS NULL AND o.status <> 'draft'
         ORDER BY om.created_at DESC LIMIT 100
       ) x ORDER BY created_at`,
      [offerId],
    );
    return rows.map((r) => ({
      id: r.id,
      // La boutique parle en son nom ; un membre, par son nom court
      authorName: r.merchant_name ?? shortName(r.full_name),
      fromMerchant: r.merchant_name !== null,
      mine: r.author_user_id === userId,
      body: r.body,
      createdAt: r.created_at.toISOString(),
    }));
  }

  /** Écrire sous une offre publiée. Un employé de la boutique de l'offre parle au nom de la boutique. */
  async post(actor: Actor & { id: string }, offerId: string, body: string) {
    const text = body.trim();
    if (text.length === 0) throw new BadRequestException('Écrivez votre message.');
    return this.db.transaction(actor, async (q) => {
      const offer = await q.query<{ status: string; merchant_id: string }>(
        'SELECT status, merchant_id FROM offers WHERE id = $1',
        [offerId],
      );
      if (!offer.rows[0] || offer.rows[0].status === 'draft') throw new NotFoundException('Offre introuvable.');
      const recent = await q.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM offer_messages
         WHERE author_user_id = $1 AND created_at > now() - interval '10 minutes'`,
        [actor.id],
      );
      if (recent.rows[0].n >= MESSAGES_PER_10_MIN) {
        throw new HttpException('Trop de messages d’un coup. Attendez quelques minutes.', HttpStatus.TOO_MANY_REQUESTS);
      }
      const staff = await q.query<{ id: string }>(
        'SELECT id FROM merchant_members WHERE merchant_id = $1 AND user_id = $2 AND removed_at IS NULL',
        [offer.rows[0].merchant_id, actor.id],
      );
      const { rows } = await q.query<{ id: string; created_at: Date }>(
        `INSERT INTO offer_messages (offer_id, author_user_id, merchant_member_id, body)
         VALUES ($1, $2, $3, $4) RETURNING id, created_at`,
        [offerId, actor.id, staff.rows[0]?.id ?? null, text],
      );
      return { id: rows[0].id, fromMerchant: staff.rows.length > 0, body: text, createdAt: rows[0].created_at.toISOString() };
    });
  }
}
