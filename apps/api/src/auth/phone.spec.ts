import { normalizeDrcPhone } from './phone.js';

describe('normalizeDrcPhone', () => {
  it.each([
    ['0970000001', '+243970000001'],
    ['970000001', '+243970000001'],
    ['243970000001', '+243970000001'],
    ['00243970000001', '+243970000001'],
    ['+243 97 000 0001', '+243970000001'],
    ['0812-345-678', '+243812345678'],
  ])('%s → %s', (input, expected) => {
    expect(normalizeDrcPhone(input)).toBe(expected);
  });

  it.each([
    ['', 'vide'],
    ['0170000001', 'ne commence ni par 8 ni par 9'],
    ['+33612345678', 'hors RDC'],
    ['097000000', 'trop court'],
    ['09700000011', 'trop long'],
    ['09700O0001', 'lettre'],
  ])('refuse %s (%s)', (input) => {
    expect(normalizeDrcPhone(input)).toBeNull();
  });
});
