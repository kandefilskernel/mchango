import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'group_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _maxMembers = TextEditingController(text: '10');
  String _currency = 'CDF';
  String _frequency = 'weekly';
  DateTime _startDate = DateTime.now().add(const Duration(days: 7));

  /// Erreurs affichées sous chaque champ, après un premier essai de validation.
  String? _nameError, _amountError, _membersError;

  @override
  void initState() {
    super.initState();
    // L'aperçu « chaque bénéficiaire reçoit… » suit la saisie
    for (final c in [_amount, _maxMembers]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _maxMembers.dispose();
    super.dispose();
  }

  String get _startIso =>
      '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _create() async {
    final amount = parseAmount(_amount.text, _currency);
    final max = int.tryParse(_maxMembers.text.trim());
    setState(() {
      _nameError = _name.text.trim().length < 2 ? 'Donnez un nom à la tontine.' : null;
      _amountError = amount == null || amount <= 0
          ? 'Entrez un montant en chiffres, par exemple ${_currency == 'USD' ? '20' : '20000'}.'
          : null;
      _membersError = max == null || max < 2 || max > 100 ? 'Entre 2 et 100 membres.' : null;
    });
    if (_nameError != null || _amountError != null || _membersError != null) return;

    final group = await Services.of(context).api.createGroup(
      name: _name.text.trim(),
      currency: _currency,
      contributionAmountMinor: amount!,
      frequency: _frequency,
      startDate: _startIso,
      maxMembers: max!,
    );
    if (!mounted) return;
    await Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(groupId: group.id)));
  }

  /// Montant reçu par chaque bénéficiaire si le groupe est complet.
  Widget _payoutPreview(BuildContext context) {
    final amount = parseAmount(_amount.text, _currency);
    final max = int.tryParse(_maxMembers.text.trim());
    if (amount == null || amount <= 0 || max == null || max < 2 || max > 100) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const Icon(Icons.savings_outlined, color: Brand.green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Avec '),
                  TextSpan(
                    text: '$max membres',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ', chaque bénéficiaire recevra '),
                  TextSpan(
                    text: formatAmount(amount * (max - 1), _currency),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.green),
                  ),
                  const TextSpan(text: ' à son tour (les cotisations des autres membres).'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUsd = _currency == 'USD';
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle tontine')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Section(
            title: 'La tontine',
            children: [
              TextField(
                key: const Key('group_name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nom de la tontine',
                  hintText: 'Ex. : Kwetu – achat véhicule',
                  helperText: "Vous pouvez y mettre l'objectif du groupe.",
                  errorText: _nameError,
                ),
              ),
            ],
          ),
          _Section(
            title: 'La cotisation',
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'CDF', label: Text('Francs (FC)')),
                  ButtonSegment(value: 'USD', label: Text('Dollars (\$)')),
                ],
                selected: {_currency},
                onSelectionChanged: (s) => setState(() {
                  _currency = s.first;
                  _amount.clear();
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('group_amount'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(decimal: isUsd),
                inputFormatters: [FilteringTextInputFormatter.allow(isUsd ? RegExp(r'[0-9.,]') : RegExp(r'[0-9 ]'))],
                decoration: InputDecoration(
                  labelText: 'Montant versé par chaque membre à chaque tour',
                  hintText: isUsd ? 'Ex. : 20' : 'Ex. : 20 000',
                  suffixText: isUsd ? '\$' : 'FC',
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Un tour'),
                items: [for (final e in frequencyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
            ],
          ),
          _Section(
            title: 'Les membres',
            children: [
              TextField(
                key: const Key('group_max_members'),
                controller: _maxMembers,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: InputDecoration(
                  labelText: 'Nombre de membres prévu',
                  helperText: 'Un membre reçoit à chaque tour : autant de tours que de membres.',
                  errorText: _membersError,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Brand.ink.withValues(alpha: 0.15)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.event, color: Brand.green),
                  title: const Text('Premier tour'),
                  subtitle: Text(formatDate(_startIso)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickDate,
                ),
              ),
              _payoutPreview(context),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Chaque membre paie directement le bénéficiaire du tour. $noCustodyNotice',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Créer la tontine', icon: Icons.check, onPressed: _create),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: Brand.green, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
        ),
        ...children,
      ],
    ),
  );
}
