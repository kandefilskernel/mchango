import { Injectable, NotFoundException } from '@nestjs/common';
import { Db } from '../infra/database.js';
import { activeMembership } from './membership.js';

const MAX_PAGE = 500;

export interface EventRow {
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
}

const EVENT_COLUMNS = `a.chain_id, a.seq, a.prev_hash, a.actor_type, a.actor_id, a.device_id, a.action,
  to_char(a.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS created_at,
  a.payload, a.signature, a.hash,
  CASE a.actor_type WHEN 'user' THEN u.full_name WHEN 'staff' THEN 'Équipe Mchango' END AS actor_name`;

function toEvent(r: EventRow) {
  return {
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
  };
}

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
    const { rows } = await this.db.query<EventRow>(
      `SELECT ${EVENT_COLUMNS}
       FROM audit_log a
       LEFT JOIN users u ON a.actor_type = 'user' AND u.id = a.actor_id
       WHERE a.chain_id = $1 AND a.seq > $2
       ORDER BY a.seq
       LIMIT $3`,
      [chainId, afterSeq, Math.min(limit, MAX_PAGE)],
    );
    return { chainId, events: rows.map(toEvent) };
  }

  /**
   * Travailleurs : les chaînes privées des cotisations (db/024_private_slot_chains.sql) que ce membre
   * a le droit de lire, chacune en entier pour être vérifiée : les siennes comme payeur, celles des
   * tours où il est bénéficiaire, celles où il est témoin ; toutes pour le président.
   */
  async privateHistory(userId: string, groupId: string) {
    const me = await activeMembership(this.db, userId, groupId);
    if (!me) throw new NotFoundException('Groupe introuvable.');
    const { rows } = await this.db.query<EventRow & { cycle_number: number; payer_id: string; payer_name: string }>(
      `WITH slots AS (
         SELECT DISTINCT a.chain_id,
                split_part(a.chain_id, ':', 4)::int AS cycle_number,
                split_part(a.chain_id, ':', 5)::uuid AS payer_id
         FROM audit_log a
         WHERE a.group_id = $1 AND a.chain_id LIKE 'group:%:slot:%'
       ), visible AS (
         SELECT s.* FROM slots s
         JOIN cycles c ON c.group_id = $1 AND c.cycle_number = s.cycle_number
         WHERE $3 = 'president'
            OR s.payer_id = $2
            OR c.beneficiary_membership_id = $2
            OR EXISTS (SELECT 1 FROM contributions k
                       WHERE k.cycle_id = c.id AND k.payer_membership_id = s.payer_id
                         AND k.witness_membership_id = $2)
       )
       SELECT ${EVENT_COLUMNS}, v.cycle_number, v.payer_id, pu.full_name AS payer_name
       FROM visible v
       JOIN audit_log a ON a.chain_id = v.chain_id
       LEFT JOIN users u ON a.actor_type = 'user' AND u.id = a.actor_id
       JOIN memberships pm ON pm.id = v.payer_id JOIN users pu ON pu.id = pm.user_id
       ORDER BY v.cycle_number, pu.full_name, a.chain_id, a.seq`,
      [groupId, me.id, me.role],
    );
    const chains = new Map<string, { chainId: string; cycleNumber: number; payer: { membershipId: string; fullName: string }; events: ReturnType<typeof toEvent>[] }>();
    for (const r of rows) {
      let c = chains.get(r.chain_id);
      if (!c) {
        c = { chainId: r.chain_id, cycleNumber: r.cycle_number, payer: { membershipId: r.payer_id, fullName: r.payer_name }, events: [] };
        chains.set(r.chain_id, c);
      }
      c.events.push(toEvent(r));
    }
    return { chains: [...chains.values()] };
  }
}
