import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services.dart';
import 'theme.dart';

/// Choix de la langue : quatre boutons, chaque langue écrite dans sa propre langue.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, this.onChanged});

  /// Appelé après le changement (ex. : enregistrer la langue sur le serveur).
  final ValueChanged<AppLanguage>? onChanged;

  @override
  Widget build(BuildContext context) {
    final store = Services.of(context).store;
    return ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, _) => Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in AppLanguage.values)
            ChoiceChip(
              key: Key('lang_${l.code}'),
              label: Text(l.label),
              selected: Lang.instance.current == l,
              selectedColor: Brand.mint,
              onSelected: (_) async {
                await Lang.instance.set(l, store);
                onChanged?.call(l);
              },
            ),
        ],
      ),
    );
  }
}

/// Fenêtre de choix de la langue, depuis le menu de l'accueil.
Future<void> showLanguageDialog(BuildContext context, {ValueChanged<AppLanguage>? onChanged}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    icon: const Icon(Icons.translate, size: 36),
    title: Text(t('Langue')),
    content: LanguagePicker(
      onChanged: (l) {
        onChanged?.call(l);
        Navigator.pop(context);
      },
    ),
  ),
);
