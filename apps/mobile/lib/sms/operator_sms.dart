/// Lecture d'un SMS de confirmation mobile money (Airtel Money, M-Pesa…) pour éviter les fautes
/// de frappe sur l'ID de transaction. Tout se passe sur le téléphone : seuls l'ID et le montant
/// sont utilisés, le texte du SMS n'est ni envoyé ni gardé.
///
/// Ce n'est pas une preuve de paiement (un texte peut être inventé) : la preuve reste la
/// confirmation par le bénéficiaire.
library;

enum SmsKind {
  /// Argent envoyé à quelqu'un (ce que le payeur colle pour déclarer).
  sent,

  /// Argent reçu, ou dépôt sur son compte (ce que le bénéficiaire peut comparer).
  received,

  /// Retrait chez un agent : ni un envoi ni une réception entre membres.
  withdrawal,

  unknown,
}

class OperatorSms {
  const OperatorSms({required this.kind, this.txId, this.amountMinor, this.currency, this.method});

  final SmsKind kind;

  /// ID de transaction, en majuscules (comme le normalise le serveur).
  final String? txId;

  /// Montant de l'opération en unités mineures (centimes pour USD, francs pour CDF), sans le solde.
  final int? amountMinor;
  final String? currency;

  /// Moyen de paiement reconnu à la forme de l'ID (« airtel », « mpesa »), ou null si incertain.
  final String? method;
}

// Airtel Money : « Trans ID: XX261023.2305.R45862 » ou « TID:CO261019.1034.T00551 »
final _airtelId = RegExp(r'\b(?:Trans\s*ID|TID)\s*:\s*([A-Z]{2}\d{6}\.\d{4}\.[A-Z]\d{4,})', caseSensitive: false);
// « Reference de la transaction:DH2769HLCYN » (format M-Pesa supposé : à confirmer sur d'autres SMS)
final _referenceId = RegExp(r'R[ée]f[ée]rence\s+de\s+la\s+transaction\s*:\s*([A-Z0-9]{6,20})', caseSensitive: false);
// Repli : « ID: … », « Ref: … », « Réf. … »
final _genericId = RegExp(r'\b(?:Trans(?:action)?\s*ID|ID|R[ée]f\.?)\s*[:.]?\s*([A-Z0-9][A-Z0-9.]{5,24}[A-Z0-9])', caseSensitive: false);

final _currency = r'(USD|CDF|FC|\$)';
final _number = r'(\d[\d  ]*(?:[.,]\d+)?)';
final _montant = RegExp('Montant\\s*:?\\s*$_number\\s*$_currency', caseSensitive: false);
final _currencyFirst = RegExp('\\b$_currency\\s*$_number', caseSensitive: false);
final _amountFirst = RegExp('$_number\\s*$_currency', caseSensitive: false);

/// Lit le SMS. Renvoie null si le texte ne ressemble à aucun SMS de transaction.
OperatorSms? parseOperatorSms(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;

  String? id;
  String? method;
  final airtel = _airtelId.firstMatch(t);
  if (airtel != null) {
    id = airtel[1];
    method = 'airtel';
  } else {
    id = (_referenceId.firstMatch(t) ?? _genericId.firstMatch(t))?[1];
  }

  final amount = _amount(t);
  if (id == null && amount == null) return null;

  return OperatorSms(
    kind: _kind(t),
    txId: id?.toUpperCase(),
    amountMinor: amount?.$1,
    currency: amount?.$2,
    method: method,
  );
}

SmsKind _kind(String t) {
  final s = t.toLowerCase();
  if (RegExp(r'retir').hasMatch(s)) return SmsKind.withdrawal;
  if (RegExp(r'envoy|transf[ée]r|vous avez pay[ée]|paiement de').hasMatch(s)) return SmsKind.sent;
  if (RegExp(r're[çc]u|d[ée]p[oô]t effectu[ée]').hasMatch(s)) return SmsKind.received;
  return SmsKind.unknown;
}

/// Montant de l'opération : « Montant: 20,00 USD », sinon le premier montant du SMS
/// (le solde vient toujours après).
(int, String)? _amount(String t) {
  final m = _montant.firstMatch(t);
  if (m != null) return _toMinor(m[1]!, m[2]!);
  final a = _currencyFirst.firstMatch(t);
  final b = _amountFirst.firstMatch(t);
  if (a == null && b == null) return null;
  if (b == null || (a != null && a.start < b.start)) return _toMinor(a![2]!, a[1]!);
  return _toMinor(b[1]!, b[2]!);
}

(int, String)? _toMinor(String raw, String currencyRaw) {
  final currency = switch (currencyRaw.toUpperCase()) {
    'USD' || r'$' => 'USD',
    _ => 'CDF',
  };
  var n = raw.replaceAll(RegExp(r'[  ]'), '');
  // « 20,00 » ou « 6.0000 » : le dernier séparateur suivi de chiffres est la virgule décimale
  final sep = RegExp(r'[.,](\d+)$').firstMatch(n);
  var units = n;
  var decimals = '';
  if (sep != null && !(currency == 'CDF' && sep[1]!.length == 3)) {
    units = n.substring(0, sep.start);
    decimals = sep[1]!;
  }
  units = units.replaceAll(RegExp(r'[.,]'), '');
  final whole = int.tryParse(units);
  if (whole == null) return null;
  if (currency == 'CDF') return (whole, currency);
  final cents = int.parse((decimals.padRight(2, '0')).substring(0, 2));
  return (whole * 100 + cents, currency);
}
