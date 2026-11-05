import { base32Decode, base32Encode, openSecret, sealSecret, totpCode, verifyTotp } from './totp.js';

// Vecteurs officiels de la RFC 6238 (annexe B), SHA-1, secret ASCII « 12345678901234567890 »,
// réduits à 6 chiffres (les 6 derniers des codes à 8 chiffres de la RFC).
const RFC_SECRET = base32Encode(Buffer.from('12345678901234567890'));

describe('TOTP (RFC 6238)', () => {
  it.each([
    [59, '287082'],
    [1111111109, '081804'],
    [1111111111, '050471'],
    [1234567890, '005924'],
    [2000000000, '279037'],
  ])('à t=%i s le code est %s', (t, code) => {
    expect(totpCode(RFC_SECRET, new Date(t * 1000))).toBe(code);
  });

  it('base32 aller-retour', () => {
    const bytes = Buffer.from([0, 1, 2, 250, 251, 252, 253, 254, 255, 42]);
    expect(base32Decode(base32Encode(bytes))).toEqual(bytes);
    expect(base32Encode(Buffer.from('12345678901234567890'))).toBe('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  });

  it('accepte le pas voisin (horloge décalée), refuse au-delà', () => {
    const t = new Date(1234567890 * 1000);
    expect(verifyTotp(RFC_SECRET, '005924', t)).toBe(true);
    expect(verifyTotp(RFC_SECRET, '005924', new Date(t.getTime() + 30_000))).toBe(true);
    expect(verifyTotp(RFC_SECRET, '005924', new Date(t.getTime() + 90_000))).toBe(false);
    expect(verifyTotp(RFC_SECRET, '12345', t)).toBe(false);
  });

  it('secret chiffré : déchiffrable avec la clé, illisible et infalsifiable sans', () => {
    const key = Buffer.alloc(32, 1).toString('base64');
    const sealed = sealSecret('JBSWY3DPEHPK3PXP', key);
    expect(sealed).not.toContain('JBSWY3DPEHPK3PXP');
    expect(openSecret(sealed, key)).toBe('JBSWY3DPEHPK3PXP');
    expect(() => openSecret(sealed, Buffer.alloc(32, 2).toString('base64'))).toThrow();
    const [v, iv, tag, data] = sealed.split('.');
    const tampered = [v, iv, tag, Buffer.from('XXXX').toString('base64') + data.slice(8)].join('.');
    expect(() => openSecret(tampered, key)).toThrow();
  });
});
