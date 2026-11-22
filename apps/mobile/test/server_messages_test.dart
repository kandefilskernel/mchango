import 'package:flutter_test/flutter_test.dart';
import 'package:mchango/l10n/l10n.dart';
import 'package:mchango/l10n/server_messages.dart';

void main() {
  tearDown(() => Lang.instance.current = AppLanguage.fr);

  test('message du serveur : plus simple en français, traduit dans la langue choisie', () {
    expect(serverMessage('Le groupe est complet.'), 'Ce groupe est plein.');
    Lang.instance.current = AppLanguage.ln;
    expect(serverMessage('Le groupe est complet.'), 'Lisanga oyo etondi.');
    Lang.instance.current = AppLanguage.sw;
    expect(serverMessage('Code invalide ou expiré.'), 'Msimbo huu haufanyi kazi. Omba msimbo mpya.');
  });

  test('messages avec un nombre ou une date : nombre gardé, date technique jamais montrée', () {
    expect(serverMessage('PIN incorrect. Il vous reste 3 essai(s).'), 'PIN faux. Encore 3 essai(s) possible(s).');
    final locked = serverMessage("PIN bloqué après trop d'essais. Réessayez après 2026-11-22T10:15:00.000Z.");
    expect(locked, isNot(contains('2026')));
    Lang.instance.current = AppLanguage.en;
    expect(serverMessage('PIN incorrect. Il vous reste 1 essai(s).'), 'Wrong PIN. 1 tries left.');
  });

  test('message inconnu : affiché tel quel', () {
    expect(serverMessage('Message que la table ne connaît pas.'), 'Message que la table ne connaît pas.');
  });
}
