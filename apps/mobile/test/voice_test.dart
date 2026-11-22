import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/l10n/l10n.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/common.dart';
import 'package:mchango/voice/speaker.dart';

import 'fake_backend.dart';

/// Voix simulée : garde ce qui aurait été dit.
class FakeSpeaker implements Speaker {
  final said = <String>[];

  @override
  Future<void> say(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  tearDown(() => Lang.instance.current = AppLanguage.fr);

  test('les montants se disent en mots, dans la langue choisie', () {
    expect(spoken(['Tour 1', 'Payé : 1 sur 3', 'Recevoir 60 000 FC']), 'Tour 1. Payé : 1 sur 3. Recevoir 60 000 francs');
    Lang.instance.current = AppLanguage.sw;
    expect(spoken(['20,50 \$']), '20,50 dola');
  });

  testWidgets('le bouton « Écouter » lit le texte de l\'écran', (tester) async {
    final speaker = FakeSpeaker();
    final backend = FakeBackend();
    final services = AppServices(client: backend.services().client, store: backend.services().store, speaker: speaker);
    await tester.pumpWidget(
      Services(
        services: services,
        child: MaterialApp(home: Scaffold(body: ListenButton(text: () => spoken(['Bonjour Maman Neema', '20 000 FC'])))),
      ),
    );
    await tester.tap(find.byKey(const Key('listen')));
    expect(speaker.said, ['Bonjour Maman Neema. 20 000 francs']);
  });
}
