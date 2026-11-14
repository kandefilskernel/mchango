import { randomInt } from 'node:crypto';
import {
  Inject,
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { APP_CONFIG, type AppConfig } from '../config.js';
import { Db, type Queryable } from '../infra/database.js';
import { SYSTEM, rows } from './sql.js';

export interface LifecycleReport {
  closed: number;
  cancelled: number;
  expired: number;
  fulfilled: number;
}

/**
 * Ce qui arrive sans qu'un utilisateur le demande : clôture à la date de fin, annulation
 * sous le seuil, expiration après le délai de retrait. Tout est écrit par l'auteur 'system'.
 * Plusieurs serveurs peuvent tourner : chaque offre est verrouillée (SKIP LOCKED) et les
 * transitions sont validées par la base.
 */
@Injectable()
export class PurchaseLifecycleService {
  private readonly logger = new Logger('Achats');

  constructor(private readonly db: Db) {}

  async runOnce(): Promise<LifecycleReport> {
    const report = { closed: 0, cancelled: 0, expired: 0, fulfilled: 0 };

    const due = await rows<{ id: string }>(
      this.db,
      `SELECT id FROM offers WHERE status = 'open' AND ends_at <= now() ORDER BY ends_at`,
    );
    for (const { id } of due) {
      try {
        const outcome = await this.settle(id);
        if (outcome) report[outcome] += 1;
      } catch (error) {
        // Une offre en échec ne bloque pas les autres ; elle sera reprise au prochain passage.
        this.logger.error(`offre ${id} : ${(error as Error).message}`);
      }
    }

    report.expired = await this.db.transaction(SYSTEM, async (q) =>
      (
        await rows(
          q,
          `UPDATE orders ord SET status = 'expired'
           FROM offers o
           WHERE o.id = ord.offer_id AND ord.status = 'ready'
             AND o.closed_at + make_interval(hours => o.pickup_window_hours) <= now()
           RETURNING ord.id`,
        )
      ).length,
    );

    report.fulfilled = await this.db.transaction(SYSTEM, async (q) =>
      (
        await rows(
          q,
          `UPDATE offers o SET status = 'fulfilled'
           WHERE o.status = 'closed'
             AND NOT EXISTS (SELECT FROM orders ord WHERE ord.offer_id = o.id
                             AND ord.status IN ('reserved', 'ready', 'paid'))
           RETURNING o.id`,
        )
      ).length,
    );

    return report;
  }

  /** Clôture une offre arrivée à échéance, ou l'annule si son seuil n'est pas atteint. */
  private settle(offerId: string): Promise<'closed' | 'cancelled' | null> {
    return this.db.transaction(SYSTEM, async (q) => {
      const [offer] = await rows<{ merchant_id: string }>(
        q,
        `SELECT merchant_id FROM offers
         WHERE id = $1 AND status = 'open' AND ends_at <= now()
         FOR UPDATE SKIP LOCKED`,
        [offerId],
      );
      if (!offer) return null; // déjà traitée par un autre serveur

      // L'offre est verrouillée : plus aucune réservation ne peut s'ajouter (orders_guard).
      const [progress] = await rows<{ reached_unit_price_minor: string | null }>(
        q,
        'SELECT reached_unit_price_minor FROM offer_progress WHERE offer_id = $1',
        [offerId],
      );

      if (progress.reached_unit_price_minor === null) {
        await q.query(`UPDATE offers SET status = 'cancelled' WHERE id = $1`, [offerId]);
        await q.query(`UPDATE orders SET status = 'cancelled' WHERE offer_id = $1 AND status = 'reserved'`, [
          offerId,
        ]);
        return 'cancelled';
      }

      // La base fixe elle-même le prix final au palier atteint.
      await q.query(`UPDATE offers SET status = 'closed' WHERE id = $1`, [offerId]);
      const orders = await rows<{ id: string }>(
        q,
        `SELECT id FROM orders WHERE offer_id = $1 AND status = 'reserved' ORDER BY created_at`,
        [offerId],
      );
      const codes = await this.freshPickupCodes(q, offer.merchant_id, orders.length);
      for (const [index, order] of orders.entries()) {
        await q.query(`UPDATE orders SET status = 'ready', pickup_code = $2 WHERE id = $1`, [
          order.id,
          codes[index],
        ]);
      }
      return 'closed';
    });
  }

  /**
   * Codes « MC-1234 » inutilisés par les commandes en attente de la boutique. Une collision
   * avec une clôture simultanée de la même boutique est refusée par l'index unique :
   * la transaction échoue et l'offre est reprise au passage suivant.
   */
  private async freshPickupCodes(q: Queryable, merchantId: string, count: number): Promise<string[]> {
    const taken = new Set(
      (
        await rows<{ pickup_code: string }>(
          q,
          `SELECT pickup_code FROM orders WHERE merchant_id = $1 AND status IN ('ready', 'paid')`,
          [merchantId],
        )
      ).map((row) => row.pickup_code),
    );
    // 4 chiffres tant que moins de la moitié des codes est prise, 6 au-delà.
    const digits = taken.size + count < 5000 ? 4 : 6;
    const codes: string[] = [];
    while (codes.length < count) {
      const code = `MC-${String(randomInt(10 ** digits)).padStart(digits, '0')}`;
      if (!taken.has(code)) {
        taken.add(code);
        codes.push(code);
      }
    }
    return codes;
  }
}

/** Passage périodique, sur le modèle des rappels (src/reminders). */
@Injectable()
export class PurchaseScheduler implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger('Achats');
  private timer?: NodeJS.Timeout;
  private running = false;

  constructor(
    private readonly lifecycle: PurchaseLifecycleService,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  onApplicationBootstrap() {
    if (this.config.PURCHASES_JOBS_ENABLED !== '1') return;
    this.timer = setInterval(() => void this.tick(), this.config.PURCHASES_JOBS_INTERVAL_SECONDS * 1000);
    void this.tick();
  }

  onModuleDestroy() {
    clearInterval(this.timer);
  }

  private async tick() {
    if (this.running) return;
    this.running = true;
    try {
      await this.lifecycle.runOnce();
    } catch (e) {
      this.logger.error(`Clôture des offres impossible : ${String(e)}`);
    } finally {
      this.running = false;
    }
  }
}
