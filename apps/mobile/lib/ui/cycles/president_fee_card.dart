import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';

/// Part du président pour ce tour : le bénéficiaire la paie (hors de Mchango) puis la déclare ;
/// le président confirme. Tout le groupe voit où elle en est.
class PresidentFeeCard extends StatelessWidget {
  const PresidentFeeCard({
    super.key,
    required this.groupId,
    required this.cycleNumber,
    required this.fee,
    required this.myMembershipId,
    required this.currency,
    required this.onChanged,
  });

  final String groupId;
  final int cycleNumber;
  final CycleFee fee;
  final String myMembershipId;
  final String currency;
  final Future<void> Function() onChanged;

  bool get _iPay => myMembershipId == fee.payerMembershipId;
  bool get _iAmPresident => myMembershipId == fee.presidentMembershipId;

  Future<void> _declare(BuildContext context) async {
    final result = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DeclareFeeSheet(amount: formatAmount(fee.amountMinor, currency)),
    );
    if (result == null || !context.mounted) return;
    try {
      await Services.of(context).api.declarePresidentFee(groupId, cycleNumber, method: result.$1, txReference: result.$2);
      await onChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _decide(BuildContext context, String decision) async {
    String? note;
    if (decision == 'dispute') {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Il y a un problème')),
          content: TextField(controller: controller, maxLength: 200, decoration: InputDecoration(labelText: t('Pourquoi ?'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(t('Envoyer'))),
          ],
        ),
      );
      if (note == null || note.isEmpty) return;
    }
    if (!context.mounted) return;
    await Services.of(context).api.decidePresidentFee(fee.payment!.id, decision, note: note);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = fee.payment;
    final (label, color, icon) = switch (p?.status) {
      'confirmed' => (t('Payé'), Brand.success, Icons.check_circle),
      'declared' => (t('À vérifier'), Brand.goldDark, Icons.pending_outlined),
      'disputed' => (t('Problème signalé'), Brand.danger, Icons.report_gmailerrorred),
      _ => (t('Pas encore payé'), Brand.muted, Icons.hourglass_empty),
    };
    return Card(
      key: const Key('president_fee_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Brand.goldDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('Part du président : {amount}', {'amount': formatAmount(fee.amountMinor, currency)}),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t('{p} % de la mise, payé par celui qui reçoit ce tour.', {'p': (fee.bps / 100).toStringAsFixed(fee.bps % 100 == 0 ? 0 : 1)}),
              style: TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
            if (_iPay && (p == null || p.status == 'rejected')) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('declare_president_fee'),
                onPressed: () => _declare(context),
                icon: const Icon(Icons.check),
                label: Text(t("J'ai payé le président")),
              ),
            ],
            if (_iAmPresident && p != null && (p.status == 'declared' || p.status == 'disputed')) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('confirm_president_fee'),
                onPressed: () => _decide(context, 'confirm'),
                icon: const Icon(Icons.check),
                label: Text(t("J'ai reçu")),
              ),
              if (p.status == 'declared') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _decide(context, 'dispute'),
                  icon: const Icon(Icons.error_outline),
                  label: Text(t('Il y a un problème')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Comment la part a été payée : mobile money (avec le numéro du SMS) ou en main.
class _DeclareFeeSheet extends StatefulWidget {
  const _DeclareFeeSheet({required this.amount});

  final String amount;

  @override
  State<_DeclareFeeSheet> createState() => _DeclareFeeSheetState();
}

class _DeclareFeeSheetState extends State<_DeclareFeeSheet> {
  String _method = 'mpesa';
  final _tx = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _tx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Part du président : {amount}', {'amount': widget.amount}), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in ['mpesa', 'airtel', 'orange', 'cash'])
              ChoiceChip(
                key: Key('fee_method_$m'),
                label: Text(methodLabels[m] ?? m),
                selected: _method == m,
                onSelected: (_) => setState(() => _method = m),
              ),
          ],
        ),
        if (_method != 'cash') ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('fee_tx'),
            controller: _tx,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: t('Numéro de la transaction'), errorText: _error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('send_president_fee'),
          onPressed: () {
            if (_method != 'cash' && _tx.text.trim().length < 5) {
              setState(() => _error = t("Entrez le numéro de la transaction reçu par SMS."));
              return;
            }
            Navigator.pop(context, (_method, _method == 'cash' ? null : _tx.text.trim()));
          },
          child: Text(t("J'ai payé le président")),
        ),
      ],
    ),
  );
}
