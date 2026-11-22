import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';

/// Mon objectif d'épargne dans une tontine : à quoi servira la mise que je recevrai à mon tour
/// (spec/goals.md). Personnel ; montré au groupe seulement si je le choisis.
class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key, required this.groupId, required this.groupName, required this.currency});

  final String groupId;
  final String groupName;
  final String currency;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Mon objectif'))),
    // Enveloppé dans un record : Loader prend une donnée null pour « pas encore chargé »
    body: Loader<(SavingsGoal?,)>(
      load: () async => (await Services.of(context).api.goal(groupId),),
      builder: (context, data, _) =>
          _GoalForm(groupId: groupId, groupName: groupName, currency: currency, initial: data.$1),
    ),
  );
}

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.groupId, required this.groupName, required this.currency, this.initial});

  final String groupId;
  final String groupName;
  final String currency;
  final SavingsGoal? initial;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late String _kind = widget.initial?.kind ?? 'school';
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _amount = TextEditingController(
    text: widget.initial?.targetAmountMinor == null
        ? ''
        : _editable(widget.initial!.targetAmountMinor!, widget.currency),
  );
  late String? _date = widget.initial?.targetDate;
  late bool _shared = widget.initial?.sharedWithGroup ?? false;
  String? _labelError, _amountError;

  /// Montant déjà enregistré, sous la forme qu'on retape : « 20000 », « 20,50 ».
  static String _editable(int minor, String currency) {
    if (currency != 'USD') return '$minor';
    final cents = minor % 100;
    return cents == 0 ? '${minor ~/ 100}' : '${minor ~/ 100},${cents.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = first.add(const Duration(days: 365 * 3));
    // Une date déjà passée (objectif ancien) ferait échouer le calendrier : on la ramène dans la plage
    var initial = _date == null ? first.add(const Duration(days: 30)) : DateTime.parse(_date!);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (picked != null) {
      setState(() => _date = picked.toIso8601String().substring(0, 10));
    }
  }

  Future<void> _save() async {
    final amountText = _amount.text.trim();
    final amount = amountText.isEmpty ? null : parseAmount(amountText, widget.currency);
    setState(() {
      _labelError = _label.text.trim().length < 2 ? t('Décrivez votre objectif en quelques mots.') : null;
      _amountError = amountText.isNotEmpty && (amount == null || amount <= 0)
          ? t('Entrez un montant en chiffres, ou laissez vide.')
          : null;
    });
    if (_labelError != null || _amountError != null) return;
    await Services.of(context).api.setGoal(
      widget.groupId,
      SavingsGoal(
        kind: _kind,
        label: _label.text.trim(),
        targetAmountMinor: amount,
        targetDate: _date,
        sharedWithGroup: _shared,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    await Services.of(context).api.removeGoal(widget.groupId);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Text(widget.groupName, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          t('À quoi servira la mise que vous recevrez à votre tour ? Un objectif clair aide à tenir jusqu\'au bout.'),
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in goalKindLabels.entries)
              ChoiceChip(
                key: Key('goal_kind_${e.key}'),
                avatar: Icon(goalKindIcons[e.key], size: 18),
                label: Text(e.value),
                selected: _kind == e.key,
                onSelected: (_) => setState(() => _kind = e.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('goal_label'),
          controller: _label,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: t('Mon objectif'),
            hintText: t('Ex. : minerval des enfants, stock de pagnes'),
            errorText: _labelError,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('goal_amount'),
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t('Montant visé (facultatif)'),
            helperText: t('Vide : la mise complète que vous recevrez.'),
            suffixText: widget.currency == 'USD' ? '\$' : 'FC',
            errorText: _amountError,
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event, color: Brand.green),
          title: Text(t('Pour quand (facultatif)')),
          subtitle: Text(_date == null ? t('Pas de date') : formatDate(_date!)),
          trailing: _date == null
              ? const Icon(Icons.edit_calendar_outlined)
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _date = null)),
          onTap: _pickDate,
        ),
        SwitchListTile(
          key: const Key('goal_shared'),
          contentPadding: EdgeInsets.zero,
          value: _shared,
          onChanged: (v) => setState(() => _shared = v),
          title: Text(t('Montrer mon objectif au groupe')),
          subtitle: Text(t('Les membres le verront dans le tableau des tours. Le montant reste privé.')),
        ),
        const SizedBox(height: 16),
        BusyButton(label: t('Enregistrer mon objectif'), icon: Icons.check, onPressed: _save),
        if (widget.initial != null) ...[
          const SizedBox(height: 12),
          BusyButton(label: t('Retirer mon objectif'), icon: Icons.delete_outline, outlined: true, onPressed: _remove),
        ],
      ],
    );
  }
}

/// Barre de progression d'un objectif (carnet).
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({super.key, required this.goal, required this.currency});

  final GoalProgress goal;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(goalKindIcons[g.kind] ?? Icons.flag_outlined, size: 18, color: Brand.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (g.reached) const Icon(Icons.emoji_events, size: 18, color: Brand.goldDark),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: g.progressPercent / 100,
            minHeight: 8,
            color: g.reached ? Brand.goldDark : Brand.green,
            backgroundColor: Brand.mint,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          g.reached
              ? t('Objectif atteint : {amount} reçus', {'amount': formatAmount(g.progressMinor, currency)})
              : t('{done} sur {target} ({p} %)', {
                  'done': formatAmount(g.progressMinor, currency),
                  'target': formatAmount(g.effectiveTargetMinor, currency),
                  'p': g.progressPercent,
                }),
          style: TextStyle(color: Brand.muted, fontSize: 14),
        ),
      ],
    );
  }
}
