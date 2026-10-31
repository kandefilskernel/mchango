import { airtelIdDate, levelOf, score } from './risk.js';

describe('score de risque', () => {
  it('seuils : vert < 30, orange 30-59, rouge ≥ 60', () => {
    expect([0, 29, 30, 59, 60, 100].map(levelOf)).toEqual(['green', 'green', 'orange', 'orange', 'red', 'red']);
  });

  it('additionne les points, plafonné à 100', () => {
    expect(score([])).toEqual({ score: 0, level: 'green', reasons: [] });
    expect(score(['first_payment', 'sms_not_pasted'])).toMatchObject({ score: 20, level: 'green' });
    expect(score(['sms_amount_mismatch', 'first_payment'])).toMatchObject({ score: 40, level: 'orange' });
    expect(score(['tx_reused_after_rejection'])).toMatchObject({ score: 60, level: 'red' });
    expect(score(['tx_reused_after_rejection', 'tx_date_mismatch', 'payer_rejected_before']).score).toBe(100);
  });
});

describe('date inscrite dans un ID Airtel', () => {
  it.each([
    ['CO261019.1034.T00551', '2026-10-19'],
    ['XX261023.2305.R45862', '2026-10-23'],
  ])('%s → %s', (id, date) => {
    expect(airtelIdDate(id)).toBe(date);
  });

  it.each([['DH2769HLCYN'], ['CO261340.1034.T00551'], [null]])('pas de date pour %s', (id) => {
    expect(airtelIdDate(id)).toBeNull();
  });
});
