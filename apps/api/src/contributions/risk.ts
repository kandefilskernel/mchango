import type { Queryable } from '../infra/database.js';

/**
 * Couche 2 du contrôle anti-fraude : un score par déclaration, à partir de règles simples.
 * Aucune règle ne prouve une fraude ; ensemble, elles disent au bénéficiaire quand vérifier.
 *   vert   (< 30)  : rien d'inhabituel ;
 *   orange (30-59) : « vérifiez votre solde avant de confirmer » (case à cocher obligatoire) ;
 *   rouge  (≥ 60)  : confirmation seulement avec l'ID du SMS reçu par le bénéficiaire.
 * Mchango ne touche jamais à l'argent : le score ne bloque que le bouton « J'ai reçu ».
 */
export const RISK_POINTS = {
  /** Même ID déjà présenté puis rejeté : un vieux SMS ou une capture réutilisée ? */
  tx_reused_after_rejection: 60,
  /** La date inscrite dans l'ID Airtel (AAMMJJ) est loin du jour de la déclaration. */
  tx_date_mismatch: 40,
  /** Le SMS collé par le payeur ne donne pas le montant de la cotisation. */
  sms_amount_mismatch: 30,
  /** Le payeur a des déclarations rejetées ces 90 derniers jours (toutes tontines). */
  payer_rejected_before: 30,
  /** Contestations contre ce payeur ces 90 derniers jours (hors celles réglées en sa faveur). */
  payer_disputed_before: 25,
  /** Au moins 3 déclarations du même membre en 30 minutes (toutes tontines). */
  burst: 25,
  /** SMS collé mais de forme inconnue (ni Airtel, ni « Référence de la transaction »). */
  sms_format_unknown: 15,
  /** Mobile money : ID tapé à la main, sans coller le SMS (une faute de frappe est aussi possible). */
  sms_not_pasted: 10,
  /** Premier paiement de ce membre dans cette tontine : pas encore d'historique. */
  first_payment: 10,
  /** Déclaré plus de 14 jours après l'échéance. */
  late_declaration: 10,
} as const;

export type RiskCode = keyof typeof RISK_POINTS;
export type RiskLevel = 'green' | 'orange' | 'red';

export const ORANGE_FROM = 30;
export const RED_FROM = 60;

/** Ce que l'app du payeur a constaté en lisant le SMS collé. Déclaratif : il ne fait qu'ajouter des points. */
export interface SmsCheck {
  pasted: boolean;
  format?: 'airtel' | 'reference' | 'generic';
  amountMatches?: boolean;
}

export function levelOf(score: number): RiskLevel {
  return score >= RED_FROM ? 'red' : score >= ORANGE_FROM ? 'orange' : 'green';
}

/** Date (AAAA-MM-JJ) inscrite dans un ID Airtel « CO261019.1034.T00551 », sinon null. */
export function airtelIdDate(txReference: string | null): string | null {
  const m = /^[A-Z]{2}(\d{2})(\d{2})(\d{2})\.\d{4}\./.exec(txReference ?? '');
  if (!m) return null;
  const [, yy, mm, dd] = m;
  const iso = `20${yy}-${mm}-${dd}`;
  const d = new Date(`${iso}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== iso ? null : iso;
}

export function score(codes: RiskCode[]) {
  const reasons = codes.map((code) => ({ code, points: RISK_POINTS[code] }));
  const total = Math.min(100, reasons.reduce((s, r) => s + r.points, 0));
  return { score: total, level: levelOf(total), reasons };
}

/**
 * Calcule et enregistre le risque d'une déclaration qui vient d'être insérée (même transaction).
 * [today] : date du jour à Lubumbashi, pour comparer avec la date de l'ID Airtel.
 */
export async function assessContribution(
  q: Queryable,
  c: { id: string; group_id: string; payer_membership_id: string; method: string; tx_reference: string | null; due_date: string },
  smsCheck: SmsCheck | undefined,
) {
  const { rows } = await q.query<{
    today: string;
    reused: boolean;
    rejected: boolean;
    disputed: boolean;
    burst: number;
    confirmed_here: boolean;
  }>(
    `WITH me AS (SELECT user_id FROM memberships WHERE id = $2)
     SELECT (now() AT TIME ZONE 'Africa/Lubumbashi')::date::text AS today,
            ($4::text IS NOT NULL AND EXISTS (
              SELECT 1 FROM contributions o WHERE o.id <> $1 AND o.method = $3::pay_method
                AND o.tx_reference = $4 AND o.status = 'rejected')) AS reused,
            EXISTS (SELECT 1 FROM contributions o JOIN memberships m ON m.id = o.payer_membership_id
                    WHERE m.user_id = (SELECT user_id FROM me) AND o.status = 'rejected'
                      AND o.declared_at > now() - interval '90 days') AS rejected,
            EXISTS (SELECT 1 FROM disputes d JOIN contributions o ON o.id = d.contribution_id
                    JOIN memberships m ON m.id = o.payer_membership_id
                    WHERE m.user_id = (SELECT user_id FROM me) AND o.id <> $1
                      AND d.status IN ('open', 'resolved_rejected')
                      AND d.opened_at > now() - interval '90 days') AS disputed,
            (SELECT count(*)::int FROM contributions o JOIN memberships m ON m.id = o.payer_membership_id
             WHERE m.user_id = (SELECT user_id FROM me) AND o.declared_at > now() - interval '30 minutes') AS burst,
            EXISTS (SELECT 1 FROM contributions o WHERE o.payer_membership_id = $2 AND o.status = 'confirmed') AS confirmed_here`,
    [c.id, c.payer_membership_id, c.method, c.tx_reference],
  );
  const f = rows[0];
  const codes: RiskCode[] = [];
  if (f.reused) codes.push('tx_reused_after_rejection');
  const idDate = airtelIdDate(c.tx_reference);
  if (idDate) {
    const days = (Date.parse(f.today) - Date.parse(idDate)) / 86_400_000;
    if (days > 3 || days < -1) codes.push('tx_date_mismatch');
  }
  if (c.method !== 'cash') {
    if (!smsCheck?.pasted) codes.push('sms_not_pasted');
    else {
      if (smsCheck.amountMatches === false) codes.push('sms_amount_mismatch');
      if (smsCheck.format === 'generic') codes.push('sms_format_unknown');
    }
  }
  if (f.rejected) codes.push('payer_rejected_before');
  if (f.disputed) codes.push('payer_disputed_before');
  if (f.burst >= 3) codes.push('burst');
  if (!f.confirmed_here) codes.push('first_payment');
  if ((Date.parse(f.today) - Date.parse(c.due_date)) / 86_400_000 > 14) codes.push('late_declaration');

  const result = score(codes);
  await q.query(
    `INSERT INTO contribution_risk (contribution_id, score, level, reasons, sms_check) VALUES ($1, $2, $3, $4, $5)`,
    [c.id, result.score, result.level, JSON.stringify(result.reasons), smsCheck ? JSON.stringify(smsCheck) : null],
  );
  return result;
}

