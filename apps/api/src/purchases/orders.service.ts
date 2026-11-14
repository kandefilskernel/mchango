import { createHash } from 'node:crypto';
import { Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { z } from 'zod';
import { Db, type Actor } from '../infra/database.js';
import { rows, toApi } from './sql.js';

const payMethod = z.enum(['mpesa', 'airtel', 'orange', 'cash', 'other']);
const txReference = z
  .string()
  .trim()
  .min(4)
  .max(100)
  .transform((value) => value.toUpperCase());
const needsReference = (dto: { method: string; txReference?: string }) =>
  dto.method === 'cash' || dto.txReference !== undefined;

export const reserveSchema = z.strictObject({
  quantity: z.int().min(1).max(1000),
  pickupName: z.string().trim().min(1).max(150),
  offlineId: z.uuid(),
  shareToken: z.string().min(16).max(200).optional(),
});
export type ReserveInput = z.infer<typeof reserveSchema>;

export const updateOrderSchema = z
  .strictObject({
    quantity: z.int().min(1).max(1000).optional(),
    pickupName: z.string().trim().min(1).max(150).optional(),
  })
  .refine((dto) => dto.quantity !== undefined || dto.pickupName !== undefined, {
    message: 'rien à modifier',
  });
export type UpdateOrderInput = z.infer<typeof updateOrderSchema>;

export const paymentSchema = z
  .strictObject({ method: payMethod, txReference: txReference.optional() })
  .refine(needsReference, { message: 'identifiant de transaction obligatoire hors espèces' });
export type PaymentInput = z.infer<typeof paymentSchema>;

export const merchantPaymentSchema = z
  .strictObject({ method: payMethod.default('cash'), txReference: txReference.optional() })
  .refine(needsReference, { message: 'identifiant de transaction obligatoire hors espèces' });
export type MerchantPaymentInput = z.infer<typeof merchantPaymentSchema>;

export const pickupSchema = z.strictObject({ pickupCode: z.string().trim().min(1).max(12) });

export const merchantOrdersQuery = z.strictObject({
  status: z.enum(['ready', 'paid', 'picked_up', 'expired']).optional(),
});

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

// Montant dû = quantité × prix final fixé par la base à la clôture. Avant la clôture,
// seul un total indicatif existe (palier atteint à cet instant).
const ORDER_SELECT = `
  SELECT ord.id, ord.offer_id, ord.quantity, ord.pickup_name, ord.status, ord.created_at,
         o.title, o.unit_label, o.currency, o.status AS offer_status, o.ends_at,
         o.final_unit_price_minor,
         ord.quantity * o.final_unit_price_minor AS amount_due_minor,
         ord.quantity * p.reached_unit_price_minor AS indicative_total_minor,
         o.closed_at + make_interval(hours => o.pickup_window_hours) AS pickup_deadline,
         m.id AS merchant_id, m.name AS merchant_name, m.address AS merchant_address,
         (SELECT pay.status FROM order_payments pay
          WHERE pay.order_id = ord.id AND pay.status <> 'rejected'
          ORDER BY pay.created_at DESC LIMIT 1) AS payment_status`;

const ORDER_FROM = `
  FROM orders ord
  JOIN offers o ON o.id = ord.offer_id
  JOIN merchants m ON m.id = ord.merchant_id
  JOIN offer_progress p ON p.offer_id = o.id`;

// L'acheteur ne voit son code que tant qu'il sert à retirer.
const BUYER_CODE = `,
  CASE WHEN ord.status IN ('ready', 'paid') THEN ord.pickup_code END AS pickup_code`;

@Injectable()
export class OrdersService {
  constructor(private readonly db: Db) {}

  // ---------- Acheteur ----------

  /** Réserve. Rejouer la même requête (même offlineId) renvoie la commande existante. */
  async reserve(actor: Actor, userId: string, offerId: string, input: ReserveInput) {
    const [existing] = await rows<{ id: string }>(
      this.db,
      `SELECT id FROM orders WHERE offline_id = $1 AND buyer_user_id = $2 AND offer_id = $3`,
      [input.offlineId, userId, offerId],
    );
    if (existing) return this.getMine(userId, existing.id);

    const id = await this.db.transaction(actor, async (q) => {
      // Origine de l'invitation : un jeton inconnu n'empêche pas de commander.
      const [share] = input.shareToken
        ? await rows<{ id: string }>(q, 'SELECT id FROM shares WHERE token_hash = $1 AND offer_id = $2', [
            hashToken(input.shareToken),
            offerId,
          ])
        : [];
      const [order] = await rows<{ id: string }>(
        q,
        `INSERT INTO orders (offer_id, merchant_id, buyer_user_id, quantity, pickup_name,
                             via_share_id, offline_id)
         SELECT o.id, o.merchant_id, $2::uuid, $3::int, $4::text, $5::uuid, $6::uuid
         FROM offers o WHERE o.id = $1 AND o.status <> 'draft'
         RETURNING id`,
        [offerId, userId, input.quantity, input.pickupName, share?.id ?? null, input.offlineId],
      );
      if (!order) throw new NotFoundException('Offre introuvable.');
      return order.id;
    });
    return this.getMine(userId, id);
  }

  async update(actor: Actor, userId: string, orderId: string, input: UpdateOrderInput) {
    await this.db.transaction(actor, async (q) => {
      const updated = await rows(
        q,
        `UPDATE orders
         SET quantity = coalesce($3, quantity), pickup_name = coalesce($4, pickup_name)
         WHERE id = $1 AND buyer_user_id = $2 RETURNING id`,
        [orderId, userId, input.quantity ?? null, input.pickupName ?? null],
      );
      if (updated.length === 0) throw new NotFoundException('Commande introuvable.');
    });
    return this.getMine(userId, orderId);
  }

  async cancel(actor: Actor, userId: string, orderId: string) {
    await this.db.transaction(actor, async (q) => {
      const updated = await rows(
        q,
        `UPDATE orders SET status = 'cancelled' WHERE id = $1 AND buyer_user_id = $2 RETURNING id`,
        [orderId, userId],
      );
      if (updated.length === 0) throw new NotFoundException('Commande introuvable.');
    });
    return this.getMine(userId, orderId);
  }

  /** L'acheteur déclare avoir payé. Ne rend pas la commande « payée » : la boutique confirme. */
  async declarePayment(actor: Actor, userId: string, orderId: string, input: PaymentInput) {
    await this.db.transaction(actor, async (q) => {
      const inserted = await rows(
        q,
        `INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, tx_reference,
                                     declared_by_user_id)
         SELECT ord.id, ord.merchant_id, ord.quantity * o.final_unit_price_minor,
                $3::pay_method, $4::text, $2::uuid
         FROM orders ord JOIN offers o ON o.id = ord.offer_id
         WHERE ord.id = $1 AND ord.buyer_user_id = $2::uuid
           AND o.final_unit_price_minor IS NOT NULL
         RETURNING id`,
        [orderId, userId, input.method, input.txReference ?? null],
      );
      if (inserted.length === 0) throw new NotFoundException('Commande introuvable ou offre non clôturée.');
    });
    return this.getMine(userId, orderId);
  }

  async listMine(userId: string) {
    return toApi(
      await rows(
        this.db,
        `${ORDER_SELECT}${BUYER_CODE}${ORDER_FROM}
         WHERE ord.buyer_user_id = $1 ORDER BY ord.created_at DESC LIMIT 200`,
        [userId],
      ),
    );
  }

  private async getMine(userId: string, orderId: string) {
    const [order] = await rows(
      this.db,
      `${ORDER_SELECT}${BUYER_CODE}${ORDER_FROM} WHERE ord.id = $1 AND ord.buyer_user_id = $2`,
      [orderId, userId],
    );
    return toApi(order);
  }

  // ---------- Boutique ----------

  /** Commandes d'une boutique après clôture (à encaisser, à remettre, remises, expirées). */
  async listForMerchant(merchantId: string, status?: string) {
    return toApi(
      await rows(
        this.db,
        `${ORDER_SELECT}, ord.pickup_code${ORDER_FROM}
         WHERE ord.merchant_id = $1
           AND ord.status = ANY (coalesce($2::order_status[], '{ready,paid}'::order_status[]))
         ORDER BY ord.pickup_code
         LIMIT 500`,
        [merchantId, status ? [status] : null],
      ),
    );
  }

  /**
   * La boutique encaisse : confirme la déclaration de l'acheteur s'il y en a une,
   * sinon enregistre elle-même le paiement. La commande passe à « payée ».
   */
  async confirmPayment(
    actor: Actor,
    merchantId: string,
    memberId: string,
    orderId: string,
    input: MerchantPaymentInput,
  ) {
    await this.db.transaction(actor, async (q) => {
      const [order] = await rows(q, 'SELECT id FROM orders WHERE id = $1 AND merchant_id = $2 FOR UPDATE', [
        orderId,
        merchantId,
      ]);
      if (!order) throw new NotFoundException('Commande introuvable.');
      const confirmed = await rows(
        q,
        `UPDATE order_payments SET status = 'confirmed', confirmed_by_member_id = $2
         WHERE id = (SELECT id FROM order_payments
                     WHERE order_id = $1 AND status = 'declared'
                     ORDER BY created_at DESC LIMIT 1)
         RETURNING id`,
        [orderId, memberId],
      );
      if (confirmed.length === 0) {
        await q.query(
          `INSERT INTO order_payments (order_id, merchant_id, amount_minor, method, tx_reference,
                                       status, confirmed_by_member_id)
           SELECT ord.id, ord.merchant_id, ord.quantity * o.final_unit_price_minor,
                  $2::pay_method, $3::text, 'confirmed', $4::uuid
           FROM orders ord JOIN offers o ON o.id = ord.offer_id
           WHERE ord.id = $1`,
          [orderId, input.method, input.txReference ?? null, memberId],
        );
      }
      await q.query(`UPDATE orders SET status = 'paid' WHERE id = $1`, [orderId]);
    });
    return this.getForMerchant(merchantId, orderId);
  }

  /** La boutique remet le produit, sur présentation du code de retrait. */
  async confirmPickup(actor: Actor, merchantId: string, memberId: string, orderId: string, pickupCode: string) {
    await this.db.transaction(actor, async (q) => {
      const [order] = await rows<{ pickup_code: string | null }>(
        q,
        'SELECT pickup_code FROM orders WHERE id = $1 AND merchant_id = $2 FOR UPDATE',
        [orderId, merchantId],
      );
      if (!order) throw new NotFoundException('Commande introuvable.');
      if (order.pickup_code?.toUpperCase() !== pickupCode.toUpperCase()) {
        throw new UnprocessableEntityException('Code de retrait incorrect.');
      }
      await q.query(`INSERT INTO pickups (order_id, merchant_id, confirmed_by_member_id) VALUES ($1, $2, $3)`, [
        orderId,
        merchantId,
        memberId,
      ]);
      await q.query(`UPDATE orders SET status = 'picked_up' WHERE id = $1`, [orderId]);
    });
    return this.getForMerchant(merchantId, orderId);
  }

  private async getForMerchant(merchantId: string, orderId: string) {
    const [order] = await rows(
      this.db,
      `${ORDER_SELECT}, ord.pickup_code${ORDER_FROM} WHERE ord.id = $1 AND ord.merchant_id = $2`,
      [orderId, merchantId],
    );
    return toApi(order);
  }
}
