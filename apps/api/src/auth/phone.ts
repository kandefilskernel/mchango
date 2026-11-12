/**
 * Normalise un numéro mobile congolais au format E.164 (+243XXXXXXXXX).
 * Accepte : 0970000001, 970000001, 243970000001, 00243970000001, +243 97 000 0001.
 * Renvoie null si le numéro n'est pas un mobile RDC valide.
 *
 * Les numéros mobiles RDC commencent par 8 ou 9 après l'indicatif (à revoir si
 * l'ARPTC ouvre d'autres plages).
 */
export function normalizeDrcPhone(input: string): string | null {
  const s = input.replace(/[\s.\-()]/g, '');
  const national =
    /^\+243\d{9}$/.test(s) ? s.slice(4)
    : /^00243\d{9}$/.test(s) ? s.slice(5)
    : /^243\d{9}$/.test(s) ? s.slice(3)
    : /^0\d{9}$/.test(s) ? s.slice(1)
    : /^\d{9}$/.test(s) ? s
    : null;
  if (!national || !/^[89]\d{8}$/.test(national)) return null;
  return `+243${national}`;
}
