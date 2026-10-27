import type { Queryable } from '../infra/database.js';

/**
 * Données d'une tontine préparées pour l'analyse : PSEUDONYMISÉES (M1, M2… à la place des noms,
 * aucun numéro de téléphone, aucun identifiant interne). La table de correspondance reste sur
 * le serveur et sert seulement à réafficher les vrais noms dans le back-office.
 */
export interface GroupDataset {
  group: { currency: string; amountMinor: number; frequency: string; status: string; members: number };
  members: { code: string; role: string; turn: number | null }[];
  contributions: {
    cycle: number;
    payer: string;
    receiver: string;
    witness: string | null;
    method: string;
    amountMinor: number;
    status: string;
    late: boolean;
    hoursToConfirm: number | null;
    hoursSinceDeclared: number;
    txReferenceReused: boolean;
  }[];
  disputes: { cycle: number; openedBy: string; against: string; status: string; reason: string }[];
  feedback: { member: string; rating: number | null; text: string }[];
}

/** Anomalie trouvée par une règle simple, sans IA : toujours disponible, même sans clé d'API. */
export interface Signal {
  rule: string;
  severity: 'info' | 'attention' | 'urgent';
  members: string[];
  detail: string;
}

export interface Pseudonyms {
  /** M1 → id de l'adhésion : gardé sur le serveur pour réafficher les vrais noms dans le back-office */
  codes: Record<string, string>;
}

const PHONE = /\+?\d[\d\s.-]{7,}\d/g;

/** Retire numéros de téléphone et noms des textes libres (avis, motifs de litige). */
export function scrub(text: string, nameToCode: Map<string, string>): string {
  let out = text.replace(PHONE, '[numéro]');
  for (const [name, code] of nameToCode) {
    if (name.trim().length < 3) continue;
    out = out.replace(new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi'), code);
  }
  return out.slice(0, 1000);
}

export async function groupDataset(q: Queryable, groupId: string): Promise<{ dataset: GroupDataset; pseudonyms: Pseudonyms }> {
  const g = await q.query<{ currency: string; amount: string; frequency: string; status: string }>(
    'SELECT currency, contribution_amount_minor AS amount, frequency, status FROM groups WHERE id = $1',
    [groupId],
  );
  const members = await q.query<{ id: string; full_name: string; role: string; turn_order: number | null }>(
    `SELECT m.id, u.full_name, m.role, m.turn_order FROM memberships m JOIN users u ON u.id = m.user_id
     WHERE m.group_id = $1 ORDER BY m.turn_order NULLS LAST, m.joined_at`,
    [groupId],
  );
  const code = new Map<string, string>();
  const codes: Record<string, string> = {};
  const nameToCode = new Map<string, string>();
  members.rows.forEach((m, i) => {
    const c = `M${i + 1}`;
    code.set(m.id, c);
    codes[c] = m.id;
    nameToCode.set(m.full_name, c);
  });
  const of = (id: string | null) => (id ? (code.get(id) ?? '?') : null);

  const contributions = await q.query<{
    cycle_number: number;
    payer: string;
    receiver: string;
    witness: string | null;
    method: string;
    amount: string;
    status: string;
    is_late: boolean;
    hours_to_confirm: number | null;
    hours_since: number;
    reused: boolean;
  }>(
    `SELECT c.cycle_number, k.payer_membership_id AS payer, k.receiver_membership_id AS receiver,
            k.witness_membership_id AS witness, k.method, k.amount_minor AS amount, k.status, k.is_late,
            (SELECT extract(epoch FROM min(f.confirmed_at) - k.declared_at) / 3600 FROM confirmations f
              WHERE f.contribution_id = k.id AND f.decision = 'confirm')::float AS hours_to_confirm,
            (extract(epoch FROM now() - k.declared_at) / 3600)::float AS hours_since,
            EXISTS (SELECT 1 FROM contributions o WHERE o.id <> k.id AND o.method = k.method
                      AND o.tx_reference = k.tx_reference) AS reused
     FROM contributions k JOIN cycles c ON c.id = k.cycle_id
     WHERE k.group_id = $1 ORDER BY c.cycle_number, k.declared_at`,
    [groupId],
  );
  const disputes = await q.query<{ cycle_number: number; opened_by: string; payer: string; status: string; reason: string }>(
    `SELECT c.cycle_number, d.opened_by, k.payer_membership_id AS payer, d.status, d.reason
     FROM disputes d JOIN contributions k ON k.id = d.contribution_id JOIN cycles c ON c.id = k.cycle_id
     WHERE k.group_id = $1 ORDER BY d.opened_at`,
    [groupId],
  );
  const feedback = await q.query<{ user_id: string; rating: number | null; body: string }>(
    `SELECT f.user_id, f.rating, f.body FROM member_feedback f
     WHERE f.group_id = $1 ORDER BY f.created_at DESC LIMIT 50`,
    [groupId],
  );
  const userCode = await q.query<{ user_id: string; id: string }>(
    'SELECT user_id, id FROM memberships WHERE group_id = $1',
    [groupId],
  );
  const codeOfUser = new Map(userCode.rows.map((r) => [r.user_id, code.get(r.id) ?? '?']));

  const row = g.rows[0];
  return {
    pseudonyms: { codes },
    dataset: {
      group: {
        currency: row.currency,
        amountMinor: Number(row.amount),
        frequency: row.frequency,
        status: row.status,
        members: members.rows.length,
      },
      members: members.rows.map((m) => ({ code: code.get(m.id)!, role: m.role, turn: m.turn_order })),
      contributions: contributions.rows.map((k) => ({
        cycle: k.cycle_number,
        payer: of(k.payer)!,
        receiver: of(k.receiver)!,
        witness: of(k.witness),
        method: k.method,
        amountMinor: Number(k.amount),
        status: k.status,
        late: k.is_late,
        hoursToConfirm: k.hours_to_confirm === null ? null : Math.round(k.hours_to_confirm),
        hoursSinceDeclared: Math.round(k.hours_since),
        txReferenceReused: k.reused,
      })),
      disputes: disputes.rows.map((d) => ({
        cycle: d.cycle_number,
        openedBy: of(d.opened_by)!,
        against: of(d.payer)!,
        status: d.status,
        reason: scrub(d.reason, nameToCode),
      })),
      feedback: feedback.rows.map((f) => ({
        member: codeOfUser.get(f.user_id) ?? 'ancien membre',
        rating: f.rating,
        text: scrub(f.body, nameToCode),
      })),
    },
  };
}

/** Règles simples, vérifiables, sans IA. Seuils volontairement prudents : ce sont des pistes. */
export function ruleSignals(d: GroupDataset): Signal[] {
  const out: Signal[] = [];
  // (Un montant différent de celui du groupe est déjà refusé à la déclaration : pas de règle ici.)
  for (const k of d.contributions) {
    // Possible seulement après le rejet de la première déclaration : une capture réutilisée ?
    if (k.txReferenceReused) {
      out.push({ rule: 'duplicate_reference', severity: 'urgent', members: [k.payer],
        detail: `Tour ${k.cycle} : l'ID de transaction a déjà servi dans une autre déclaration.` });
    }
    if (k.status === 'declared' && k.hoursSinceDeclared > 72) {
      out.push({ rule: 'unconfirmed', severity: 'attention', members: [k.receiver, k.payer],
        detail: `Tour ${k.cycle} : déclaré il y a ${k.hoursSinceDeclared} h, toujours pas confirmé par ${k.receiver}.` });
    }
  }
  const count = (xs: string[]) => xs.reduce<Record<string, number>>((m, x) => ((m[x] = (m[x] ?? 0) + 1), m), {});
  for (const [m, n] of Object.entries(count(d.contributions.filter((k) => k.late).map((k) => k.payer)))) {
    if (n >= 2) out.push({ rule: 'repeated_late', severity: 'attention', members: [m], detail: `${n} paiements en retard.` });
  }
  for (const [m, n] of Object.entries(count(d.disputes.map((x) => x.against)))) {
    if (n >= 2) out.push({ rule: 'repeated_disputes', severity: 'urgent', members: [m], detail: `${n} paiements contestés.` });
  }
  for (const [m, n] of Object.entries(count(d.contributions.filter((k) => k.status === 'rejected').map((k) => k.payer)))) {
    if (n >= 1) out.push({ rule: 'rejected', severity: 'attention', members: [m], detail: `${n} déclaration(s) rejetée(s).` });
  }
  // Le même témoin pour le même payeur, encore et encore : possible complicité
  const pairs = count(d.contributions.filter((k) => k.witness).map((k) => `${k.payer}|${k.witness}`));
  for (const [pair, n] of Object.entries(pairs)) {
    if (n >= 2) {
      const [payer, witness] = pair.split('|');
      out.push({ rule: 'same_witness', severity: 'info', members: [payer, witness],
        detail: `${witness} est témoin de ${payer} pour ${n} paiements en espèces.` });
    }
  }
  return out;
}
