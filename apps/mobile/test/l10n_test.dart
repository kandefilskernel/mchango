import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/app.dart';
import 'package:mchango/l10n/l10n.dart';
import 'package:mchango/storage/key_value_store.dart';

import 'fake_backend.dart';

/// Tous les textes passés à t('…') dans lib/ (le texte français sert de clé).
Set<String> keysUsedInCode() {
  final literal = RegExp(r"""\bt\(\s*(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")""");
  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
    for (final m in literal.allMatches(f.readAsStringSync())) {
      keys.add((m[1] ?? m[2])!.replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1] == 'n' ? '\n' : e[1]!));
    }
  }
  return keys;
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  tearDown(() => Lang.instance.current = AppLanguage.fr);

  test('chaque texte de l\'app existe en swahili, lingala et anglais, avec les mêmes variables', () {
    final keys = keysUsedInCode();
    expect(keys.length, greaterThan(250));
    final vars = RegExp(r'\{\w+\}');
    Set<String> varsOf(String s) => vars.allMatches(s).map((m) => m[0]!).toSet();
    for (final MapEntry(key: lang, value: table) in translationTables.entries) {
      final missing = keys.where((k) => !table.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '${lang.label} : textes non traduits');
      for (final k in keys) {
        expect(varsOf(table[k]!), varsOf(k), reason: '${lang.label} : variables de « $k »');
      }
    }
  });

  test('t() : traduction, variables, repli sur le français', () {
    Lang.instance.current = AppLanguage.en;
    expect(t('Bonjour {name}', {'name': 'Furaha'}), 'Hello Furaha');
    expect(t('Texte inconnu'), 'Texte inconnu');
    Lang.instance.current = AppLanguage.sw;
    expect(t('Mes tontines'), 'Likelemba zangu');
    Lang.instance.current = AppLanguage.fr;
    expect(t('Bonjour {name}', {'name': 'Furaha'}), 'Bonjour Furaha');
  });

  testWidgets('choisir le lingala sur le premier écran : l\'app change de langue, et s\'en souvient', (tester) async {
    final store = MemoryKeyValueStore()..data['onboarding_done'] = '1';
    final services = FakeBackend().services(store);
    await services.auth.load();
    await tester.pumpWidget(MchangoApp(services: services));
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();
    expect(find.text('Bienvenue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lang_ln')));
    await tester.pumpAndSettle();
    expect(find.text('Boyei malamu'), findsOneWidget);
    expect(find.text('Zwa kode na SMS'), findsOneWidget);
    expect(store.data['language'], 'ln');

    await Lang.instance.load(store);
    expect(Lang.instance.current, AppLanguage.ln);
  });
}
