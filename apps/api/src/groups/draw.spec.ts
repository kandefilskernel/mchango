import { readFileSync } from 'node:fs';
import { drawTurnOrder, membersHash } from './draw.js';

const vectors = JSON.parse(
  readFileSync(new URL('../../../../spec/test-vectors/draw.json', import.meta.url), 'utf8'),
) as {
  cases: { description: string; seed: string; members: string[]; members_hash: string; order: string[] }[];
};

describe('tirage de l’ordre des tours', () => {
  it.each(vectors.cases)('vecteur commun : $description', (c) => {
    expect(membersHash(c.members)).toBe(c.members_hash);
    expect(drawTurnOrder(c.members, c.seed)).toEqual(c.order);
  });

  const members = vectors.cases[0].members;

  it("ne dépend pas de l'ordre dans lequel on fournit les membres", () => {
    const seed = 'ab'.repeat(32);
    expect(drawTurnOrder([...members].reverse(), seed)).toEqual(drawTurnOrder(members, seed));
    expect(membersHash([...members].reverse())).toBe(membersHash(members));
  });

  it('donne une permutation des membres', () => {
    const order = drawTurnOrder(members, '01'.repeat(32));
    expect([...order].sort()).toEqual([...members].sort());
  });

  it('une autre graine donne en général un autre ordre', () => {
    const orders = new Set(
      Array.from({ length: 20 }, (_, k) =>
        drawTurnOrder(members, k.toString(16).padStart(2, '0').repeat(32)).join(),
      ),
    );
    expect(orders.size).toBeGreaterThan(10);
  });

  it('refuse une graine qui ne fait pas 32 octets', () => {
    expect(() => drawTurnOrder(members, 'abcd')).toThrow();
  });
});
