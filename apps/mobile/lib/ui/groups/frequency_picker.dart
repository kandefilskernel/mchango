import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';

/// « Tous les combien ? » : trois gros choix, chacun avec son image, plutôt qu'un menu caché.
/// Le président choisit par jour, par semaine ou par mois. Les codes sont ceux de l'API.
class FrequencyPicker extends StatelessWidget {
  const FrequencyPicker({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static List<(String, IconData, String, String)> get choices => [
    ('daily', Icons.today_rounded, t('Chaque jour'), t('Un tour par jour')),
    ('weekly', Icons.view_week_rounded, t('Chaque semaine'), t('Un tour par semaine')),
    ('monthly', Icons.calendar_month_rounded, t('Chaque mois'), t('Un tour par mois')),
  ];

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('frequency_picker'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (code, icon, label, caption) in choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: value == code ? Brand.mint : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: value == code ? Brand.green : Brand.ink.withValues(alpha: 0.15),
                width: value == code ? 2 : 1,
              ),
            ),
            child: InkWell(
              key: Key('frequency_$code'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(code),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 30, color: Brand.green),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          Text(caption, style: TextStyle(fontSize: 14, color: Brand.muted)),
                        ],
                      ),
                    ),
                    if (value == code) const Icon(Icons.check_circle, color: Brand.green, size: 28),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
