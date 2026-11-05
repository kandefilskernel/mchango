import { hash, verify } from '@node-rs/argon2';

/**
 * 6 chiffres : différent par construction du PIN mobile money (4 chiffres chez la
 * plupart des opérateurs), qu'il ne faut surtout pas réutiliser.
 */
export const PIN_LENGTH = 6;

/** Renvoie la raison du refus, ou null si le PIN est acceptable. */
export function pinWeakness(pin: string): string | null {
  if (!/^\d{6}$/.test(pin)) return 'Le PIN doit contenir exactement 6 chiffres.';
  if (/^(\d)\1{5}$/.test(pin)) return 'Le PIN ne doit pas répéter un seul chiffre.';
  const d = pin.split('').map(Number);
  const ascending = d.every((v, i) => i === 0 || v === (d[i - 1] + 1) % 10);
  const descending = d.every((v, i) => i === 0 || v === (d[i - 1] + 9) % 10);
  if (ascending || descending) return 'Le PIN ne doit pas être une suite (123456, 987654…).';
  return null;
}

// Argon2id (algorithme par défaut de @node-rs/argon2), paramètres recommandés par l'OWASP.
const ARGON2_OPTIONS = { memoryCost: 19456, timeCost: 2, parallelism: 1 };

export function hashPin(pin: string): Promise<string> {
  return hash(pin, ARGON2_OPTIONS);
}

export function verifyPin(pinHash: string, pin: string): Promise<boolean> {
  return verify(pinHash, pin);
}
