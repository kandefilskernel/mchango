import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'frequency_picker.dart';
import 'president_fee_picker.dart';

/// Le président change les règles avant le démarrage : nom, montant, tous les combien, date du
/// premier tour, nombre de personnes. Chacun devra signer de nouveau : on le dit avant d'enregistrer.
class EditGroupScreen extends StatefulWidget {
  const EditGroupScreen({super.key, required this.group});

  final Group group;

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
  late final _name = TextEditingController(text: widget.group.name);
  late final _amount = TextEditingController(text: _editable(widget.group.contributionAmountMinor, widget.group.currency));
  late final _max = TextEditingController(text: '${widget.group.maxMembers}');
  late String _frequency = widget.group.frequency;
  late DateTime _startDate = DateTime.parse(widget.group.startDate);
  late int _presidentFeeBps = widget.group.presidentFeeBps;
  String? _nameError, _amountError, _maxError;

  /// Montant déjà enregistré, sous la forme qu'on retape : « 20000 », « 20,50 ».
  static String _editable(int minor, String currency) {
    if (currency != 'USD') return '$minor';
    final cents = minor % 100;
    return cents == 0 ? '${minor ~/ 100}' : '${minor ~/ 100},${cents.toString().padLeft(2, '0')}';
  }

  String get _startIso =>
      '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isBefore(today) ? today : _startDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    final g = widget.group;
    final amount = parseAmount(_amount.text, g.currency);
    final max = int.tryParse(_max.text.trim());
    final minPeople = g.members.length < 2 ? 2 : g.members.length;
    setState(() {
      _nameError = _name.text.trim().length < 2 ? t('Donnez un nom à la tontine.') : null;
      _amountError = amount == null || amount <= 0
          ? t('Entrez un montant en chiffres, par exemple {example}.', {'example': g.currency == 'USD' ? '20' : '20000'})
          : null;
      _maxError = max == null || max < minPeople || max > 100
          ? t('Entre {min} et 100 personnes.', {'min': minPeople})
          : null;
    });
    if (_nameError != null || _amountError != null || _maxError != null) return;

    final signed = g.terms?.signedBy.isNotEmpty ?? false;
    if (signed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Changer les règles ?')),
          content: Text(t('Chacun devra signer de nouveau.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Oui, changer'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    await Services.of(context).api.updateGroup(
      g.id,
      name: _name.text.trim(),
      contributionAmountMinor: amount,
      frequency: _frequency,
      startDate: _startIso,
      maxMembers: max,
      presidentFeeBps: _presidentFeeBps,
      // Le jour de paie n'existe que pour une tontine mensuelle
      removePayday: g.payday != null && _frequency != 'monthly',
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final usd = g.currency == 'USD';
    return Scaffold(
      appBar: AppBar(title: Text(t('Modifier la tontine'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            t('Vous pouvez changer avant le démarrage. Chacun devra signer de nouveau.'),
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('edit_name'),
            controller: _name,
            decoration: InputDecoration(labelText: t('Nom de la tontine'), errorText: _nameError),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('edit_amount'),
            controller: _amount,
            keyboardType: TextInputType.numberWithOptions(decimal: usd),
            inputFormatters: [FilteringTextInputFormatter.allow(usd ? RegExp(r'[0-9.,]') : RegExp(r'[0-9 ]'))],
            decoration: InputDecoration(
              labelText: t('Combien chacun paie à chaque tour'),
              suffixText: usd ? '\$' : 'FC',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 20),
          Text(t('Tous les combien ?'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FrequencyPicker(value: _frequency, onChanged: (v) => setState(() => _frequency = v)),
          const SizedBox(height: 16),
          PresidentFeePicker(
            bps: _presidentFeeBps,
            currency: g.currency,
            potMinor: (parseAmount(_amount.text, g.currency) ?? g.contributionAmountMinor) *
                ((int.tryParse(_max.text.trim()) ?? g.maxMembers) - 1),
            onChanged: (v) => setState(() => _presidentFeeBps = v),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Brand.ink.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              key: const Key('edit_date'),
              leading: const Icon(Icons.event, color: Brand.green),
              title: Text(t('Premier tour')),
              subtitle: Text(formatDate(_startIso)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('edit_max'),
            controller: _max,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(labelText: t('Combien de personnes ?'), errorText: _maxError),
          ),
          const SizedBox(height: 24),
          BusyButton(label: t('Enregistrer'), icon: Icons.check, onPressed: _save),
        ],
      ),
    );
  }
}
