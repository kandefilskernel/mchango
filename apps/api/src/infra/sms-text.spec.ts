import { otpMessage } from '../auth/otp.service.js';
import { LANGUAGES } from './languages.js';
import { reminderMessage, smsAmount } from '../reminders/reminders.service.js';
import { isGsm7, smsSegments, toGsm7 } from './sms-text.js';

describe('encodage des SMS', () => {
  it('GSM-7 : les accents courants du français passent, pas tous', () => {
    expect(isGsm7("Payez à Mama Furaha, déclarez-le dans l'app")).toBe(true);
    expect(isGsm7('même')).toBe(false);
    expect(isGsm7('« Kwetu »')).toBe(false);
  });

  it('toGsm7 remplace ce qui ferait passer le SMS en UCS-2', () => {
    expect(toGsm7('« Kwetu » – Mme Ngoyi, fête ç’est')).toBe(`"Kwetu" - Mme Ngoyi, fete c'est`);
    expect(isGsm7(toGsm7('Œuvre  ê î ô û …'))).toBe(true);
  });

  it('nombre de SMS facturés', () => {
    expect(smsSegments('a'.repeat(160))).toBe(1);
    expect(smsSegments('a'.repeat(161))).toBe(2);
    expect(smsSegments('ê'.repeat(70))).toBe(1);
    expect(smsSegments('ê' + 'a'.repeat(70))).toBe(2);
    expect(smsSegments('€'.repeat(80))).toBe(1);
    expect(smsSegments('€'.repeat(81))).toBe(2);
    expect(smsSegments('🙏'.repeat(35))).toBe(1);
    expect(smsSegments('🙏'.repeat(36))).toBe(2);
  });

  it.each(LANGUAGES)('le code de connexion tient en un seul SMS GSM-7 (%s)', (lang) => {
    const m = otpMessage('123456', lang);
    expect(m).toContain('123456');
    expect(isGsm7(m)).toBe(true);
    expect(smsSegments(m)).toBe(1);
  });
});

describe('texte du rappel', () => {
  const base = {
    groupName: 'Kwetu',
    cycleNumber: 3,
    amountMinor: 20000,
    currency: 'CDF',
    beneficiaryName: 'Mama Furaha',
    beneficiaryPhone: '+243991234567',
    dueDate: '2026-11-02',
    dueToday: false,
  };

  it('dit qui payer, combien, où et quand', () => {
    expect(reminderMessage(base)).toBe(
      "Mchango : Kwetu, tour 3. Payez 20 000 FC à Mama Furaha (+243991234567) d'ici le 02/11/2026, puis déclarez-le dans l'app.",
    );
    expect(reminderMessage({ ...base, dueToday: true })).toContain("aujourd'hui");
  });

  it('montants', () => {
    expect(smsAmount(20000, 'CDF')).toBe('20 000 FC');
    expect(smsAmount(1500000, 'CDF')).toBe('1 500 000 FC');
    expect(smsAmount(2050, 'USD')).toBe('20,50 $');
  });

  it('dans la langue du membre', () => {
    expect(reminderMessage(base, 'sw')).toBe(
      'Mchango: Kwetu, zamu 3. Lipa 20 000 FC kwa Mama Furaha (+243991234567) kabla ya 02/11/2026, kisha utangaze malipo kwenye app.',
    );
    expect(reminderMessage({ ...base, dueToday: true }, 'ln')).toContain('Futa 20 000 FC na Mama Furaha (+243991234567) lelo');
    expect(reminderMessage(base, 'en')).toContain('Pay 20 000 FC to Mama Furaha (+243991234567) by 02/11/2026');
  });

  it.each(LANGUAGES)("un seul SMS GSM-7 même avec des noms longs et accentués (%s)", (lang) => {
    const m = reminderMessage({
      ...base,
      groupName: '« Fête des mamans » – coopérative des maraîchères de Kenya-Lubumbashi',
      beneficiaryName: 'Françoise Kabwe Ngoyi wa Mutombo',
      amountMinor: 999_999_999_999,
      cycleNumber: 100,
    }, lang);
    expect(isGsm7(m)).toBe(true);
    expect(smsSegments(m)).toBe(1);
  });
});
