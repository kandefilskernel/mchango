import { createHash } from 'node:crypto';
import type { Queryable } from '../infra/database.js';

export const TERMS_VERSION = 'mchango-terms-v1';

export interface TermsState {
  /** Empreinte SHA-256 (hex) du règlement actuel. */
  hash: string;
  /** Règlement complet : au moins 2 membres et un tour pour chacun. Avant, rien à signer. */
  ready: boolean;
  /** Adhésions qui ont signé CE règlement. */
  signedBy: string[];
  /** Adhésions actives qui doivent encore signer. */
  missing: { membershipId: string; fullName: string }[];
  allSigned: boolean;
}

/**
 * Le règlement signé par les membres : ce qui engage chacun (montant, devise, fréquence, date de
 * début, mode de versement, et qui reçoit à quel tour). Texte canonique : JSON aux clés triées,
 * membres dans l'ordre des tours (spec/groups.md).
 */
export function termsHash(t: {
  groupId: string;
  currency: string;
  amountMinor: string | number;
  frequency: string;
  startDate: string;
  payoutMode: string;
  order: { membershipId: string; turnOrder: number | null }[];
  /** Calendrier de paie (Travailleurs). Absent : l'empreinte reste celle d'avant cette option. */
  payday?: { day: number; shift: string } | null;
}): string {
  const canonical = JSON.stringify({
    amount_minor: String(t.amountMinor),
    currency: t.currency,
    frequency: t.frequency,
    group_id: t.groupId,
    order: [...t.order]
      .sort((a, b) => (a.turnOrder ?? 1e9) - (b.turnOrder ?? 1e9) || a.membershipId.localeCompare(b.membershipId))
      .map((m) => [m.turnOrder, m.membershipId]),
    payout_mode: t.payoutMode,
    // Clé seulement si un jour de paie est fixé : les règlements sans calendrier gardent leur empreinte
    ...(t.payday ? { payday: [t.payday.day, t.payday.shift] } : {}),
    start_date: t.startDate,
    version: TERMS_VERSION,
  });
  return createHash('sha256').update(canonical).digest('hex');
}

/** État des signatures du règlement actuel d'un groupe. */
export async function termsState(q: Queryable, groupId: string): Promise<TermsState> {
  const g = await q.query<{
    currency: string;
    amount: string;
    frequency: string;
    start_date: string;
    payout_mode: string;
    payday: number | null;
    payday_shift: string | null;
  }>(
    `SELECT currency, contribution_amount_minor AS amount, frequency, start_date::text AS start_date, payout_mode,
            payday, payday_shift
     FROM groups WHERE id = $1`,
    [groupId],
  );
  const members = await q.query<{ id: string; full_name: string; turn_order: number | null }>(
    `SELECT m.id, u.full_name, m.turn_order FROM memberships m JOIN users u ON u.id = m.user_id
     WHERE m.group_id = $1 AND m.status = 'active' ORDER BY m.turn_order NULLS LAST, m.joined_at`,
    [groupId],
  );
  const row = g.rows[0];
  const hash = termsHash({
    groupId,
    currency: row.currency,
    amountMinor: row.amount,
    frequency: row.frequency,
    startDate: row.start_date,
    payoutMode: row.payout_mode,
    payday: row.payday === null ? null : { day: row.payday, shift: row.payday_shift! },
    order: members.rows.map((m) => ({ membershipId: m.id, turnOrder: m.turn_order })),
  });
  const n = members.rows.length;
  const ready = n >= 2 && members.rows.every((m) => m.turn_order !== null);
  const signed = await q.query<{ membership_id: string }>(
    'SELECT membership_id FROM group_terms_signatures WHERE group_id = $1 AND terms_hash = $2',
    [groupId, hash],
  );
  const signedBy = signed.rows.map((r) => r.membership_id);
  const missing = members.rows
    .filter((m) => !signedBy.includes(m.id))
    .map((m) => ({ membershipId: m.id, fullName: m.full_name }));
  return { hash, ready, signedBy, missing, allSigned: ready && missing.length === 0 };
}
