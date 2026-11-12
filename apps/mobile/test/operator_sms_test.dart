import 'package:flutter_test/flutter_test.dart';
import 'package:mchango/sms/operator_sms.dart';

// Formats réels, noms et numéros remplacés.
const airtelReceived =
    'Trans ID: XX261023.2305.R45862: Vous avez recu USD 6.0000 de 990000001 AIRTELMONEY-EXEMPLE. Nouveau solde est: 6.3318 USD.';
const airtelWithdrawal =
    'TID:CO261019.1034.T00551. Vous avez retire 5.0000 USD chez AGENT 990000002. Cout: 0.4500. Votre nouveau solde: 31.0018 USD.';
const referenceDeposit =
    'Le depot effectue par 1234567 - MEMBRE EXEMPLE 1234567 a reussi Montant:20,00 USD Solde disponible:34,51 USD '
    'Reference de la transaction:DH2769HLCYN le 02-08-2026 a 14:40:34.';

void main() {
  test('Airtel Money, réception : ID, montant (pas le solde), moyen', () {
    final s = parseOperatorSms(airtelReceived)!;
    expect(s.txId, 'XX261023.2305.R45862');
    expect(s.amountMinor, 600);
    expect(s.currency, 'USD');
    expect(s.kind, SmsKind.received);
    expect(s.method, 'airtel');
  });

  test('Airtel Money, retrait chez un agent : reconnu comme retrait', () {
    final s = parseOperatorSms(airtelWithdrawal)!;
    expect(s.txId, 'CO261019.1034.T00551');
    expect(s.amountMinor, 500);
    expect(s.kind, SmsKind.withdrawal);
  });

  test('dépôt avec « Reference de la transaction » : virgule décimale, montant avant le solde', () {
    final s = parseOperatorSms(referenceDeposit)!;
    expect(s.txId, 'DH2769HLCYN');
    expect(s.amountMinor, 2000);
    expect(s.currency, 'USD');
    expect(s.kind, SmsKind.received);
    expect(s.method, isNull, reason: 'opérateur pas encore confirmé pour ce format');
  });

  test('envoi en francs, montant avec espaces', () {
    final s = parseOperatorSms('Vous avez envoye 20 000 CDF a MAMA EXEMPLE. ID: AB12CD34EF. Solde: 45 500 CDF')!;
    expect(s.kind, SmsKind.sent);
    expect(s.txId, 'AB12CD34EF');
    expect(s.amountMinor, 20000);
    expect(s.currency, 'CDF');
  });

  test('texte sans transaction : rien', () {
    expect(parseOperatorSms('Bonjour, rendez-vous demain au marché'), isNull);
    expect(parseOperatorSms(''), isNull);
  });
}
