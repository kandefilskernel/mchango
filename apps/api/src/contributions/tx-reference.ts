/**
 * Référence de transaction normalisée : majuscules, sans espaces. Les formats exacts
 * des opérateurs (M-Pesa, Airtel Money, Orange Money) sont à confirmer avec de vrais
 * SMS : on ne vérifie ici qu'une forme plausible.
 * Fichier à part : les cotisations et la part du président s'en servent, sans import circulaire.
 */
export function normalizeTxReference(input: string): string | null {
  const ref = input.toUpperCase().replace(/\s/g, '');
  return /^[A-Z0-9][A-Z0-9.-]{4,29}$/.test(ref) ? ref : null;
}
