import { normalizeTxReference } from './contributions.service.js';

describe('normalizeTxReference', () => {
  it.each([
    ['rk45tx9qpl', 'RK45TX9QPL'],
    ['  RK45 TX9 QPL ', 'RK45TX9QPL'],
    ['CI230915.1423.A12345', 'CI230915.1423.A12345'],
    ['PP-2026-0001', 'PP-2026-0001'],
  ])('%s → %s', (input, expected) => {
    expect(normalizeTxReference(input)).toBe(expected);
  });

  it.each([
    ['', 'vide'],
    ['AB12', 'trop court'],
    ['A'.repeat(31), 'trop long'],
    ['-AB1234', 'commence par un tiret'],
    ['AB12#34', 'caractère spécial'],
  ])('refuse %s (%s)', (input) => {
    expect(normalizeTxReference(input)).toBeNull();
  });
});
