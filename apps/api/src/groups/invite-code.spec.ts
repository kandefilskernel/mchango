import { generateInviteCode, inviteCodeHash, normalizeInviteCode } from './invite-code.js';

describe("code d'invitation", () => {
  it('format XXXX-XXXX sans caractères ambigus', () => {
    for (let i = 0; i < 200; i++) {
      expect(generateInviteCode()).toMatch(/^[2-9A-HJKMNP-TV-Z]{4}-[2-9A-HJKMNP-TV-Z]{4}$/);
    }
  });

  it('accepte la saisie en minuscules, avec espaces ou sans tiret', () => {
    expect(normalizeInviteCode('k7mp-q2xw')).toBe('K7MPQ2XW');
    expect(normalizeInviteCode(' K7MP Q2XW ')).toBe('K7MPQ2XW');
    expect(normalizeInviteCode('K7MPQ2XW')).toBe('K7MPQ2XW');
  });

  it.each([
    ['K7MP-Q2X', 'trop court'],
    ['K7MP-Q2XWA', 'trop long'],
    ['K7MP-Q2X0', 'zéro'],
    ['K7MP-Q2XO', 'lettre O'],
    ['K7MP-Q2XI', 'lettre I'],
  ])('refuse %s (%s)', (input) => {
    expect(normalizeInviteCode(input)).toBeNull();
  });

  it("l'empreinte dépend du secret serveur", () => {
    const a = inviteCodeHash('K7MPQ2XW', 'secret-a'.repeat(4));
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(inviteCodeHash('K7MPQ2XW', 'secret-b'.repeat(4))).not.toBe(a);
  });
});
