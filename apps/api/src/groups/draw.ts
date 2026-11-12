import { createHash, createHmac } from 'node:crypto';

/** Version de l'algorithme, publiée avec chaque tirage (spec/draw.md). */
export const DRAW_ALGORITHM = 'mchango-draw-v1';

/** Empreinte de la liste des membres tirés : ids triés, joints par '\n', SHA-256 hex. */
export function membersHash(membershipIds: string[]): string {
  return createHash('sha256').update(sortedIds(membershipIds).join('\n')).digest('hex');
}

/**
 * Ordre des tours tiré à partir d'une graine publique (64 caractères hex).
 * Mélange de Fisher-Yates sur les ids triés ; l'indice j de l'étape i vient des 8
 * premiers octets de HMAC-SHA256(graine, "mchango-draw-v1:<i>") modulo (i + 1).
 * Le biais du modulo (≤ 100 / 2^64) est négligeable.
 *
 * Renvoie les ids dans l'ordre de passage : le premier reçoit au tour 1.
 */
export function drawTurnOrder(membershipIds: string[], seedHex: string): string[] {
  const key = Buffer.from(seedHex, 'hex');
  if (key.length !== 32) throw new Error('graine invalide : 32 octets attendus');
  const order = sortedIds(membershipIds);
  for (let i = order.length - 1; i > 0; i--) {
    const mac = createHmac('sha256', key).update(`${DRAW_ALGORITHM}:${i}`).digest();
    const j = Number(mac.readBigUInt64BE(0) % BigInt(i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order;
}

function sortedIds(ids: string[]): string[] {
  // Comparaison par code de caractère (pas localeCompare) : identique dans tous les langages
  return ids.map((id) => id.toLowerCase()).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}
