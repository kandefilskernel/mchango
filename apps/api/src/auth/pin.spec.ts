import { hashPin, pinWeakness, verifyPin } from './pin.js';

describe('pinWeakness', () => {
  it.each(['482915', '102938', '774411'])('accepte %s', (pin) => {
    expect(pinWeakness(pin)).toBeNull();
  });

  it.each([
    ['1234', 'trop court'],
    ['1234567', 'trop long'],
    ['12a456', 'lettre'],
    ['000000', 'chiffre répété'],
    ['123456', 'suite croissante'],
    ['654321', 'suite décroissante'],
    ['890123', 'suite qui boucle'],
  ])('refuse %s (%s)', (pin) => {
    expect(pinWeakness(pin)).not.toBeNull();
  });
});

describe('hashPin / verifyPin', () => {
  it('argon2id, vérifiable, jamais le PIN en clair', async () => {
    const h = await hashPin('482915');
    expect(h.startsWith('$argon2id$')).toBe(true);
    expect(h).not.toContain('482915');
    expect(await verifyPin(h, '482915')).toBe(true);
    expect(await verifyPin(h, '482916')).toBe(false);
  });
});
