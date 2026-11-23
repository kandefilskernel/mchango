import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../util/format.dart';
import '../theme.dart';

/// Part du président : de 0 à 10 %, à discuter avec les membres. Chacun la voit dans le règlement
/// et l'accepte en signant. Valeur en points de base (100 = 1 %), comme l'API.
class PresidentFeePicker extends StatelessWidget {
  const PresidentFeePicker({
    super.key,
    required this.bps,
    required this.onChanged,
    this.potMinor,
    this.currency = 'CDF',
  });

  final int bps;
  final ValueChanged<int> onChanged;

  /// Mise d'un tour (montant × (membres − 1)), pour montrer ce que la part représente.
  final int? potMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final fee = potMinor == null ? null : presidentFeeAmount(potMinor!, bps);
    return Column(
      key: const Key('president_fee_picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Part du président'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          t('À discuter avec les membres. Chacun la verra dans le règlement avant de signer.'),
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var p = 0; p <= 10; p++)
              ChoiceChip(
                key: Key('fee_$p'),
                label: Text(p == 0 ? t('Aucune') : '$p %', style: const TextStyle(fontSize: 16)),
                selected: bps == p * 100,
                onSelected: (_) => onChanged(p * 100),
              ),
          ],
        ),
        if (bps > 0 && fee != null) ...[
          const SizedBox(height: 10),
          Text(
            t('Celui qui reçoit son tour donne {amount} au président.', {'amount': formatAmount(fee, currency)}),
            key: const Key('president_fee_example'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }
}
