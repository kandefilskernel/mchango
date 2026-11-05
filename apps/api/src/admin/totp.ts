import { createCipheriv, createDecipheriv, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

// Codes à usage unique (RFC 6238, TOTP) : 6 chiffres, 30 secondes, HMAC-SHA1.
// Compatible avec Google Authenticator, Microsoft Authenticator, Aegis, etc.

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const STEP_SECONDS = 30;

export function base32Encode(bytes: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(text: string): Buffer {
  const clean = text.toUpperCase().replace(/[\s=-]/g, '');
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const c of clean) {
    const v = ALPHABET.indexOf(c);
    if (v < 0) throw new Error('secret base32 invalide');
    value = (value << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

/** Nouveau secret de 160 bits, en base32 (à saisir ou scanner dans l'application d'authentification). */
export function newTotpSecret(): string {
  return base32Encode(randomBytes(20));
}

export function totpCode(secretBase32: string, at: Date = new Date()): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(at.getTime() / 1000 / STEP_SECONDS)));
  const mac = createHmac('sha1', base32Decode(secretBase32)).update(counter).digest();
  const offset = mac[mac.length - 1] & 0x0f;
  const binary = mac.readUInt32BE(offset) & 0x7fffffff;
  return (binary % 1_000_000).toString().padStart(6, '0');
}

/** Accepte le code du pas courant et des pas voisins (horloge du téléphone un peu décalée). */
export function verifyTotp(secretBase32: string, code: string, at: Date = new Date(), window = 1): boolean {
  if (!/^\d{6}$/.test(code)) return false;
  for (let i = -window; i <= window; i++) {
    const expected = totpCode(secretBase32, new Date(at.getTime() + i * STEP_SECONDS * 1000));
    if (timingSafeEqual(Buffer.from(expected), Buffer.from(code))) return true;
  }
  return false;
}

/** Lien à transformer en QR code pour l'application d'authentification. */
export function otpauthUrl(email: string, secretBase32: string): string {
  const label = encodeURIComponent(`Mchango:${email}`);
  return `otpauth://totp/${label}?secret=${secretBase32}&issuer=Mchango&algorithm=SHA1&digits=6&period=30`;
}

/** Chiffrement AES-256-GCM des secrets 2FA en base : une fuite de la base ne suffit pas. */
export function sealSecret(plain: string, keyBase64: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', Buffer.from(keyBase64, 'base64'), iv);
  const data = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return ['v1', iv.toString('base64'), cipher.getAuthTag().toString('base64'), data.toString('base64')].join('.');
}

export function openSecret(sealed: string, keyBase64: string): string {
  const [version, iv, tag, data] = sealed.split('.');
  if (version !== 'v1') throw new Error('format de secret inconnu');
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(keyBase64, 'base64'), Buffer.from(iv, 'base64'));
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8');
}
