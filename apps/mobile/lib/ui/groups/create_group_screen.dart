import 'package:flutter/material.dart';

import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import 'group_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _maxMembers = TextEditingController(text: '30');
  String _currency = 'CDF';
  String _frequency = 'weekly';
  DateTime _startDate = DateTime.now().add(const Duration(days: 7));

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
    if (_name.text.trim().length < 2) return showInfo(context, 'Donnez un nom à la tontine.');
    if (amount == null || amount <= 0) return showInfo(context, 'Montant invalide.');
    if (max == null || max < 2 || max > 100) {
      return showInfo(context, 'Le nombre de membres doit être entre 2 et 100.');
    }
    final group = await Services.of(context).api.createGroup(
          name: _name.text.trim(),
          currency: _currency,
          contributionAmountMinor: amount,
          frequency: _frequency,
          startDate: _startIso,
          maxMembers: max,
        );
    if (!mounted) return;
    await Navigator.pushReplacement(
        context, MaterialPageRoute<void>(builder: (_) => GroupScreen(groupId: group.id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle tontine')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          key: const Key('group_name'),
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'CDF', label: Text('Francs (FC)')),
            ButtonSegment(value: 'USD', label: Text('Dollars (\$)')),
          ],
          selected: {_currency},
          onSelectionChanged: (s) => setState(() => _currency = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('group_amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Cotisation de chaque membre, par tour',
            suffixText: _currency == 'USD' ? '\$' : 'FC',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _frequency,
          decoration: const InputDecoration(labelText: 'Fréquence des tours', border: OutlineInputBorder()),
          items: [
            for (final e in frequencyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _frequency = v!),
        ),
        const SizedBox(height: 16),
        ListTile(
          shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(4)),
          leading: const Icon(Icons.event),
          title: const Text('Premier tour'),
          subtitle: Text(formatDate(_startIso)),
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _maxMembers,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Nombre maximum de membres', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        const Text('Chaque membre paie directement le bénéficiaire du tour. $noCustodyNotice'),
        const SizedBox(height: 16),
        BusyButton(label: 'Créer', onPressed: _create),
      ]),
    );
  }
}
