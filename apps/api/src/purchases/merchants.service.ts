import { ForbiddenException, Injectable } from '@nestjs/common';
import { Db } from '../infra/database.js';
import { rows, toApi } from './sql.js';

@Injectable()
export class MerchantsService {
  constructor(private readonly db: Db) {}

  /** Identifiant d'employé de l'utilisateur dans cette boutique, ou 403. */
  async requireMember(userId: string, merchantId: string): Promise<string> {
    const [member] = await rows<{ id: string }>(
      this.db,
      `SELECT id FROM merchant_members
       WHERE merchant_id = $1 AND user_id = $2 AND removed_at IS NULL`,
      [merchantId, userId],
    );
    if (!member) throw new ForbiddenException("Vous n'agissez pas pour cette boutique.");
    return member.id;
  }

  /** Boutiques pour lesquelles l'utilisateur peut agir. */
  async listMine(userId: string) {
    return toApi(
      await rows(
        this.db,
        `SELECT m.id, m.name, m.address, m.status, mm.role,
                z.id AS zone_id, z.city, z.commune
         FROM merchant_members mm
         JOIN merchants m ON m.id = mm.merchant_id
         JOIN pickup_zones z ON z.id = m.zone_id
         WHERE mm.user_id = $1 AND mm.removed_at IS NULL
         ORDER BY m.name`,
        [userId],
      ),
    );
  }
}
