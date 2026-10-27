import { ruleSignals, scrub, type GroupDataset } from './signals.js';

const base = (contributions: Partial<GroupDataset['contributions'][number]>[], disputes: GroupDataset['disputes'] = []): GroupDataset => ({
  group: { currency: 'CDF', amountMinor: 20000, frequency: 'weekly', status: 'active', members: 3 },
  members: [],
  contributions: contributions.map((c) => ({
    cycle: 1,
    payer: 'M2',
    receiver: 'M1',
    witness: null,
    method: 'mpesa',
    amountMinor: 20000,
    status: 'confirmed',
    late: false,
    hoursToConfirm: 2,
    hoursSinceDeclared: 10,
    txReferenceReused: false,
    ...c,
  })),
  disputes,
  feedback: [],
});

describe('règles d’anomalies (sans IA)', () => {
  it('rien à signaler pour des paiements normaux', () => {
    expect(ruleSignals(base([{}, { payer: 'M3' }]))).toEqual([]);
  });

  it('référence réutilisée, confirmation qui traîne', () => {
    const rules = ruleSignals(
      base([{ payer: 'M3', txReferenceReused: true }, { cycle: 2, status: 'declared', hoursSinceDeclared: 100 }]),
    ).map((s) => [s.rule, s.severity, s.members]);
    expect(rules).toEqual([
      ['duplicate_reference', 'urgent', ['M3']],
      ['unconfirmed', 'attention', ['M1', 'M2']],
    ]);
  });

  it('retards et contestations répétés, même témoin pour le même payeur', () => {
    const rules = ruleSignals(
      base(
        [
          { late: true, method: 'cash', witness: 'M3' },
          { cycle: 2, late: true, method: 'cash', witness: 'M3' },
        ],
        [
          { cycle: 1, openedBy: 'M1', against: 'M2', status: 'open', reason: '' },
          { cycle: 2, openedBy: 'M1', against: 'M2', status: 'open', reason: '' },
        ],
      ),
    ).map((s) => s.rule);
    expect(rules).toEqual(['repeated_late', 'repeated_disputes', 'same_witness']);
  });
});

describe('scrub', () => {
  it('retire numéros et noms, quelle que soit la casse', () => {
    const names = new Map([['Papa Jean', 'M2']]);
    expect(scrub('papa jean au +243 990-000-001 ou 0990000001', names)).toBe('M2 au [numéro] ou [numéro]');
  });

  it('garde les petits nombres (montants, tours)', () => {
    expect(scrub('Tour 3, 20000 CDF', new Map())).toBe('Tour 3, 20000 CDF');
  });
});
