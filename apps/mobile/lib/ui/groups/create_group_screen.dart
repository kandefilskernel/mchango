import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'group_screen.dart';
import '../../l10n/l10n.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _maxMembers = TextEditingController(text: '10');
  String _category = 'community';
  String _currency = 'CDF';
  String _frequency = 'weekly';

  /// Travailleurs, tontine mensuelle : jour de paie (null = pas de calendrier de paie).
  int? _payday;
  String _paydayShift = 'before';

  bool get _paydayAllowed => _category == 'workers' && _frequency == 'monthly';
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
      _nameError = _name.text.trim().length < 2 ? t('Donnez un nom à la tontine.') : null;
      _amountError = amount == null || amount <= 0
          ? t('Entrez un montant en chiffres, par exemple {example}.', {'example': _currency == 'USD' ? '20' : '20000'})
          : null;
      _membersError = max == null || max < 2 || max > 100 ? t('Entre 2 et 100 membres.') : null;
    });
    if (_nameError != null || _amountError != null || _membersError != null) return;

    final group = await Services.of(context).api.createGroup(
      name: _name.text.trim(),
      currency: _currency,
      contributionAmountMinor: amount!,
      frequency: _frequency,
      startDate: _startIso,
      maxMembers: max!,
      category: _category,
      payday: _paydayAllowed ? _payday : null,
      paydayShift: _paydayAllowed && _payday != null ? _paydayShift : null,
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
                // Une seule phrase à traduire ; le montant reste mis en valeur là où la langue le place
                children: [
                  for (final (i, part) in t(
                    'Avec {n} membres, chaque bénéficiaire recevra {amount} à son tour (les cotisations des autres membres).',
                    {'n': max},
                  ).split('{amount}').indexed) ...[
                    if (i > 0)
                      TextSpan(
                        text: formatAmount(amount * (max - 1), _currency),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.green),
                      ),
                    TextSpan(text: part),
                  ],
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
      appBar: AppBar(title: Text(t('Nouvelle tontine'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Section(
            title: t('La catégorie'),
            children: [
              for (final c in _categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CategoryTile(
                    key: Key('category_${c.code}'),
                    icon: c.icon,
                    title: t(c.name),
                    subtitle: t(c.description),
                    selected: _category == c.code,
                    onTap: () => setState(() => _category = c.code),
                  ),
                ),
              Text(
                t("Choisissez ce qui ressemble le plus à votre groupe. Pour l'instant, toutes les catégories fonctionnent de la même façon."),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          _Section(
            title: t('La tontine'),
            children: [
              TextField(
                key: const Key('group_name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: t('Nom de la tontine'),
                  hintText: t('Ex. : Kwetu – achat véhicule'),
                  helperText: t("Vous pouvez y mettre l'objectif du groupe."),
                  errorText: _nameError,
                ),
              ),
            ],
          ),
          _Section(
            title: t('La cotisation'),
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'CDF', label: Text(t('Francs (FC)'))),
                  ButtonSegment(value: 'USD', label: Text(t('Dollars (\$)'))),
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
                  labelText: t('Montant versé par chaque membre à chaque tour'),
                  hintText: isUsd ? t('Ex. : 20') : t('Ex. : 20 000'),
                  suffixText: isUsd ? '\$' : 'FC',
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: InputDecoration(labelText: t('Un tour')),
                items: [for (final e in frequencyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              if (_paydayAllowed) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  key: const Key('group_payday'),
                  initialValue: _payday,
                  decoration: InputDecoration(
                    labelText: t('Jour de paie'),
                    helperText: t("Chaque tour tombe le jour de la paie : on cotise quand le salaire est arrivé."),
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t('Pas de jour de paie'))),
                    for (var d = 1; d <= 30; d++) DropdownMenuItem(value: d, child: Text(t('Le {day}', {'day': d}))),
                    DropdownMenuItem(value: 31, child: Text(t('Le dernier jour du mois'))),
                  ],
                  onChanged: (v) => setState(() => _payday = v),
                ),
                if (_payday != null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('group_payday_shift'),
                    initialValue: _paydayShift,
                    decoration: InputDecoration(labelText: t('Si ce jour est un dimanche ou un jour férié')),
                    items: [
                      DropdownMenuItem(value: 'before', child: Text(t('Avancer au jour ouvré précédent'))),
                      DropdownMenuItem(value: 'after', child: Text(t('Reporter au jour ouvré suivant'))),
                    ],
                    onChanged: (v) => setState(() => _paydayShift = v!),
                  ),
                ],
              ],
            ],
          ),
          _Section(
            title: t('Les membres'),
            children: [
              TextField(
                key: const Key('group_max_members'),
                controller: _maxMembers,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                decoration: InputDecoration(
                  labelText: t('Nombre de membres prévu'),
                  helperText: t('Un membre reçoit à chaque tour : autant de tours que de membres.'),
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
                  title: Text(t('Premier tour')),
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
            t('Chaque membre paie directement le bénéficiaire du tour. {notice}', {'notice': noCustodyNotice}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          BusyButton(label: t('Créer la tontine'), icon: Icons.check, onPressed: _create),
        ],
      ),
    );
  }
}

/// Catégories de tontine, du plus simple au plus évolué (spec/categories.md). Les codes sont ceux de
/// l'API (`GET /group-categories`) ; les textes sont traduits ici.
class _Category {
  const _Category(this.code, this.icon, this.name, this.description);
  final String code;
  final IconData icon;
  final String name;
  final String description;
}

const _categories = [
  _Category('community', Icons.groups_outlined, 'Communautaire', 'Voisins, amis, marchands, taxi-motos, associations de quartier.'),
  _Category('organization', Icons.apartment_outlined, 'Organisation', 'Associations, coopératives, syndicats, ONG, mutuelles.'),
  _Category('workers', Icons.work_outline, 'Travailleurs', "Collègues d'un même employeur ou d'un même métier, fonctionnaires."),
  _Category('religion', Icons.volunteer_activism_outlined, 'Religion', 'Églises, paroisses, mosquées, communautés et leurs groupes.'),
];

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Brand.mint : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: selected ? Brand.green : Brand.ink.withValues(alpha: 0.15),
        width: selected ? 2 : 1,
      ),
    ),
    child: ListTile(
      selected: selected,
      leading: Icon(icon, color: Brand.green),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check_circle, color: Brand.green) : null,
      onTap: onTap,
    ),
  );
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
