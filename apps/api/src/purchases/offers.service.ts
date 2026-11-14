import { Injectable, NotFoundException } from '@nestjs/common';
import { z } from 'zod';
import { Db, type Actor } from '../infra/database.js';
import { rows, toApi } from './sql.js';

export const createOfferSchema = z.strictObject({
  title: z.string().trim().min(1).max(150),
  description: z.string().trim().max(2000).optional(),
  unitLabel: z.string().trim().min(1).max(40),
  imageUrl: z.url().max(500).optional(),
  currency: z.enum(['CDF', 'USD']).default('CDF'),
  regularPriceMinor: z.int().positive(),
  endsAt: z.iso.datetime({ offset: true }),
  pickupWindowHours: z.int().min(24).max(336),
  tiers: z
    .array(z.strictObject({ minQuantity: z.int().positive(), unitPriceMinor: z.int().positive() }))
    .min(1)
    .max(5),
});
export type CreateOfferInput = z.infer<typeof createOfferSchema>;

export const listOffersQuery = z.strictObject({ zoneId: z.uuid().optional() });

// Le compteur et le prix atteint viennent de la vue offer_progress : jamais calculés ici.
// Aucune donnée d'acheteur dans cette projection : elle est servie sans authentification.
const OFFER_SELECT = `
  SELECT o.id, o.title, o.description, o.unit_label, o.image_url, o.currency,
         o.regular_price_minor, o.ends_at, o.pickup_window_hours, o.status,
         o.final_unit_price_minor, o.closed_at,
         m.id AS merchant_id, m.name AS merchant_name, m.address AS merchant_address,
         z.id AS zone_id, z.city, z.commune,
         p.confirmed_units, p.threshold_units, p.missing_units, p.reached_unit_price_minor,
         (SELECT coalesce(json_agg(json_build_object(
                    'min_quantity', t.min_quantity,
                    'unit_price_minor', t.unit_price_minor) ORDER BY t.min_quantity), '[]'::json)
          FROM offer_tiers t WHERE t.offer_id = o.id) AS tiers
  FROM offers o
  JOIN merchants m ON m.id = o.merchant_id
  JOIN pickup_zones z ON z.id = m.zone_id
  JOIN offer_progress p ON p.offer_id = o.id`;

@Injectable()
export class OffersService {
  constructor(private readonly db: Db) {}

  async listZones() {
    return toApi(
      await rows(this.db, `SELECT id, city, commune FROM pickup_zones WHERE is_active ORDER BY city, commune`),
    );
  }

  /** Offres ouvertes, visibles sans compte. */
  async listOpen(zoneId?: string) {
    return toApi(
      await rows(
        this.db,
        `${OFFER_SELECT}
         WHERE o.status = 'open' AND o.ends_at > now()
           AND ($1::uuid IS NULL OR z.id = $1::uuid)
         ORDER BY o.ends_at
         LIMIT 100`,
        [zoneId ?? null],
      ),
    );
  }

  /** Détail public : tout sauf les brouillons. */
  async getPublic(offerId: string) {
    const [offer] = await rows(this.db, `${OFFER_SELECT} WHERE o.id = $1 AND o.status <> 'draft'`, [offerId]);
    if (!offer) throw new NotFoundException('Offre introuvable.');
    return toApi(offer);
  }

  async listForMerchant(merchantId: string) {
    return toApi(
      await rows(
        this.db,
        `${OFFER_SELECT} WHERE o.merchant_id = $1 ORDER BY o.created_at DESC LIMIT 200`,
        [merchantId],
      ),
    );
  }

  async create(actor: Actor, merchantId: string, memberId: string, input: CreateOfferInput) {
    const id = await this.db.transaction(actor, async (q) => {
      const [offer] = await rows<{ id: string }>(
        q,
        `INSERT INTO offers (merchant_id, created_by_member_id, title, description, unit_label,
                             image_url, currency, regular_price_minor, ends_at, pickup_window_hours)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING id`,
        [
          merchantId,
          memberId,
          input.title,
          input.description ?? null,
          input.unitLabel,
          input.imageUrl ?? null,
          input.currency,
          input.regularPriceMinor,
          input.endsAt,
          input.pickupWindowHours,
        ],
      );
      for (const tier of input.tiers) {
        await q.query(
          `INSERT INTO offer_tiers (offer_id, min_quantity, unit_price_minor) VALUES ($1, $2, $3)`,
          [offer.id, tier.minQuantity, tier.unitPriceMinor],
        );
      }
      return offer.id;
    });
    return this.getForMerchant(merchantId, id);
  }

  /** draft → open. La base vérifie les paliers, la date de fin et l'état de la boutique. */
  async publish(actor: Actor, merchantId: string, offerId: string) {
    await this.db.transaction(actor, async (q) => {
      const updated = await rows(
        q,
        `UPDATE offers SET status = 'open' WHERE id = $1 AND merchant_id = $2 RETURNING id`,
        [offerId, merchantId],
      );
      if (updated.length === 0) throw new NotFoundException('Offre introuvable.');
    });
    return this.getForMerchant(merchantId, offerId);
  }

  /** Retire une offre (brouillon ou ouverte) et annule ses réservations. */
  async cancel(actor: Actor, merchantId: string, offerId: string) {
    await this.db.transaction(actor, async (q) => {
      const updated = await rows(
        q,
        `UPDATE offers SET status = 'cancelled' WHERE id = $1 AND merchant_id = $2 RETURNING id`,
        [offerId, merchantId],
      );
      if (updated.length === 0) throw new NotFoundException('Offre introuvable.');
      await q.query(`UPDATE orders SET status = 'cancelled' WHERE offer_id = $1 AND status = 'reserved'`, [
        offerId,
      ]);
    });
    return this.getForMerchant(merchantId, offerId);
  }

  private async getForMerchant(merchantId: string, offerId: string) {
    const [offer] = await rows(this.db, `${OFFER_SELECT} WHERE o.id = $1 AND o.merchant_id = $2`, [
      offerId,
      merchantId,
    ]);
    return toApi(offer);
  }
}
