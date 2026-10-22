import { createPublicKey, verify, type KeyObject } from 'node:crypto';

// En-tête DER SubjectPublicKeyInfo d'une clé Ed25519 ; suivi des 32 octets bruts.
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

/** Clé publique Ed25519 brute (32 octets) en base64 standard, telle qu'envoyée par l'app. */
export function parseEd25519PublicKey(base64: string): KeyObject | null {
  const raw = Buffer.from(base64, 'base64');
  if (raw.length !== 32 || raw.toString('base64') !== base64) return null;
  try {
    return createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
      format: 'der',
      type: 'spki',
    });
  } catch {
    return null;
  }
}

/** Message signé par l'appareil pour ouvrir une session (spec/auth.md). */
export function challengeMessage(deviceId: string, nonce: string): string {
  return `mchango-auth-v1\n${deviceId}\n${nonce}`;
}

export function verifyDeviceSignature(
  publicKeyBase64: string,
  message: string,
  signatureBase64: string,
): boolean {
  const key = parseEd25519PublicKey(publicKeyBase64);
  const signature = Buffer.from(signatureBase64, 'base64');
  if (!key || signature.length !== 64) return false;
  return verify(null, Buffer.from(message, 'utf8'), key, signature);
}
