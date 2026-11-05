import { Injectable, NotFoundException } from '@nestjs/common';
import { Db } from '../infra/database.js';
import { activeMembership } from './membership.js';

const MAX_PAGE = 500;

/**
 * Historique du groupe : les événements de sa chaîne du journal, au format exact de
 * spec/audit-hash.md, pour que l'app les vérifie elle-même (packages/mchango_audit).
 */
@Injectable()
export class HistoryService {
  constructor(private readonly db: Db) {}

  async history(userId: string, groupId: string, afterSeq: number, limit: number) {
    if (!(await activeMembership(this.db, userId, groupId))) {
      throw new NotFoundException('Groupe introuvable.');
    }
    const chainId = `group:${groupId}`;
    const { rows } = await this.db.query<{
      chain_id: string;
      seq: string;
      prev_hash: string;
      actor_type: string;
      actor_id: string | null;
      device_id: string | null;
      action: string;
      created_at: string;
      payload: string;
      signature: string | null;
      hash: string;
      actor_name: string | null;
    }>(
      `SELECT a.chain_id, a.seq, a.prev_hash, a.actor_type, a.actor_id, a.device_id, a.action,
              to_char(a.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
              a.payload, a.signature, a.hash,
              CASE a.actor_type WHEN 'user' THEN u.full_name WHEN 'staff' THEN 'Équipe Mchango' END AS actor_name
       FROM audit_log a
       LEFT JOIN users u ON a.actor_type = 'user' AND u.id = a.actor_id
       WHERE a.chain_id = $1 AND a.seq > $2
       ORDER BY a.seq
       LIMIT $3`,
      [chainId, afterSeq, Math.min(limit, MAX_PAGE)],
    );
    return {
      chainId,
      events: rows.map((r) => ({
        // Champs hachés : à transmettre tels quels au vérificateur
        chain_id: r.chain_id,
        seq: Number(r.seq),
        prev_hash: r.prev_hash,
        actor_type: r.actor_type,
        actor_id: r.actor_id,
        device_id: r.device_id,
        action: r.action,
        created_at: r.created_at,
        payload: r.payload,
        signature: r.signature,
        hash: r.hash,
        // Affichage seulement (hors hash)
        actor_name: r.actor_name,
      })),
    };
  }
}
