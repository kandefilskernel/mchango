import { createHmac, randomInt } from 'node:crypto';

// Sans 0/O, 1/I/L ni U : un code se dicte au téléphone ou se recopie sans ambiguïté.
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';
const LENGTH = 8; // 30^8 ≈ 6,5 × 10^11 combinaisons, avec limitation des essais

/** Code affichable, ex. « K7MP-Q2XW ». */
export function generateInviteCode(): string {
  const chars = Array.from({ length: LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]);
  return `${chars.slice(0, 4).join('')}-${chars.slice(4).join('')}`;
}

/** Forme canonique d'un code saisi (majuscules, sans tirets ni espaces), ou null s'il est mal formé. */
export function normalizeInviteCode(input: string): string | null {
  const code = input.toUpperCase().replace(/[\s-]/g, '');
  if (code.length !== LENGTH || code.split('').some((c) => !ALPHABET.includes(c))) return null;
  return code;
}

/**
 * Empreinte stockée en base. HMAC avec un secret serveur : une fuite de la base ne
 * permet pas de retrouver les codes en essayant toutes les combinaisons.
 */
export function inviteCodeHash(normalizedCode: string, pepper: string): string {
  return createHmac('sha256', pepper).update(`invite:${normalizedCode}`).digest('hex');
}
