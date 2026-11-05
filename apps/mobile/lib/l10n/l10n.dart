import 'package:flutter/foundation.dart';

import '../storage/key_value_store.dart';
import 'en.dart';
import 'ln.dart';
import 'sw.dart';

/// Langues de l'app. Le code est celui gardé sur le serveur (users.language).
enum AppLanguage {
  fr('fr', 'Français'),
  sw('sw', 'Kiswahili'),
  ln('ln', 'Lingála'),
  en('en', 'English');

  const AppLanguage(this.code, this.label);
  final String code;
  final String label;

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.fr);
}

/// Langue courante de l'app, gardée sur le téléphone. Changer de langue reconstruit l'interface.
class Lang extends ChangeNotifier {
  Lang._();
  static final instance = Lang._();

  static const _kLanguage = 'language';

  AppLanguage current = AppLanguage.fr;

  Future<void> load(KeyValueStore store) async {
    current = AppLanguage.fromCode(await store.read(_kLanguage));
    notifyListeners();
  }

  Future<void> set(AppLanguage language, KeyValueStore store) async {
    current = language;
    await store.write(_kLanguage, language.code);
    notifyListeners();
  }
}

/// Tables de traduction : la clé est le texte français, la valeur sa traduction.
const _tables = <AppLanguage, Map<String, String>>{
  AppLanguage.sw: sw,
  AppLanguage.ln: ln,
  AppLanguage.en: en,
};

/// Textes connus dans toutes les langues (vérifié par test/l10n_test.dart).
Map<AppLanguage, Map<String, String>> get translationTables => _tables;

/// Traduit un texte écrit en français. Les variables s'écrivent {nom} :
/// `t('Bonjour {name}', {'name': prenom})`. Texte absent d'une table : le français s'affiche.
String t(String french, [Map<String, Object?> args = const {}]) {
  var text = _tables[Lang.instance.current]?[french] ?? french;
  args.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
  return text;
}
