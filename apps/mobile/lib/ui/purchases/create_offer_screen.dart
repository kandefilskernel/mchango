import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'purchase_widgets.dart';

/// Nouvelle offre de la boutique. Une fois publiée, elle ne change plus : les acheteurs
/// s'engagent sur ces prix.
class CreateOfferScreen extends StatefulWidget {
  const CreateOfferScreen({super.key, required this.merchantId});

  final String merchantId;

  @override
  State<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _TierFields {
  final quantity = TextEditingController();
  final price = TextEditingController();

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

class _CreateOfferScreenState extends State<CreateOfferScreen> {
  final _title = TextEditingController();
  final _unit = TextEditingController();
  final _regular = TextEditingController();
  final _tiers = [_TierFields()];
  String _currency = 'CDF';
  DateTime _endsAt = DateTime.now().add(const Duration(days: 7));
  int _pickupHours = 72;
  bool _publish = true;

  @override
  void dispose() {
    for (final c in [_title, _unit, _regular]) {
      c.dispose();
    }
    for (final tier in _tiers) {
      tier.dispose();
    }
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _endsAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt),
    );
    if (!mounted) return;
    setState(() {
      _endsAt = DateTime(
        day.year,
        day.month,
        day.day,
        time?.hour ?? 18,
        time?.minute ?? 0,
      );
    });
  }

  /// Vérifie la saisie avant l'envoi ; renvoie un message d'erreur, ou null.
  String? _check(int? regular, List<OfferTier>? tiers) {
    if (_title.text.trim().isEmpty || _unit.text.trim().isEmpty)
      return t('Indiquez le produit et l\'unité.');
    if (regular == null || regular <= 0) return t('Prix habituel invalide.');
    if (tiers == null || tiers.isEmpty)
      return t('Chaque palier demande une quantité et un prix.');
    for (var i = 0; i < tiers.length; i++) {
      if (tiers[i].unitPriceMinor >= regular)
        return t('Chaque palier doit être moins cher que le prix habituel.');
      if (i > 0 &&
          (tiers[i].minQuantity <= tiers[i - 1].minQuantity ||
              tiers[i].unitPriceMinor >= tiers[i - 1].unitPriceMinor)) {
        return t(
          'Chaque palier demande plus d\'unités et un prix plus bas que le précédent.',
        );
      }
    }
    if (!_endsAt.isAfter(DateTime.now()))
      return t('La date de fin doit être dans le futur.');
    return null;
  }

  Future<void> _submit() async {
    final regular = parseAmount(_regular.text, _currency);
    List<OfferTier>? tiers = [];
    for (final f in _tiers) {
      final q = int.tryParse(f.quantity.text.trim());
      final p = parseAmount(f.price.text, _currency);
      if (q == null || q <= 0 || p == null || p <= 0) {
        tiers = null;
        break;
      }
      tiers!.add(OfferTier(minQuantity: q, unitPriceMinor: p));
    }
    final problem = _check(regular, tiers);
    if (problem != null) {
      showInfo(context, problem);
      return;
    }
    final api = Services.of(context).purchases;
    final offer = await api.createOffer(
      widget.merchantId,
      title: _title.text.trim(),
      unitLabel: _unit.text.trim(),
      currency: _currency,
      regularPriceMinor: regular!,
      endsAt: _endsAt,
      pickupWindowHours: _pickupHours,
      tiers: tiers!,
    );
    if (_publish) await api.publishOffer(widget.merchantId, offer.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          t('Nouvelle offre'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SectionCard(
            child: Column(
              children: [
                TextField(
                  key: const Key('offer_title'),
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: t('Produit (ex. Riz)'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('offer_unit'),
                  controller: _unit,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: t('Unité (ex. sac de 25 kg)'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('offer_regular'),
                        controller: _regular,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: t('Prix habituel par unité'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: Brand.mint,
                        selectedForegroundColor: Brand.green,
                      ),
                      segments: const [
                        ButtonSegment(value: 'CDF', label: Text('FC')),
                        ButtonSegment(value: 'USD', label: Text('\$')),
                      ],
                      selected: {_currency},
                      onSelectionChanged: (s) =>
                          setState(() => _currency = s.first),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SectionCard(
            title: t('Paliers de prix'),
            icon: Icons.stairs_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    'Le premier palier est le seuil : en dessous, l\'offre est annulée à la date de fin.',
                  ),
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
                for (final (i, f) in _tiers.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Brand.mint,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Brand.green,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: Key('tier_qty_$i'),
                            controller: f.quantity,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: t('À partir de (unités)'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: Key('tier_price_$i'),
                            controller: f.price,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: t('Prix par unité'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_tiers.length < 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      key: const Key('add_tier'),
                      onPressed: () =>
                          setState(() => _tiers.add(_TierFields())),
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text(t('Ajouter un palier')),
                    ),
                  ),
              ],
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event, color: Brand.green),
                  title: Text(t('Fin de l\'offre')),
                  subtitle: Text(
                    formatDateTime(_endsAt),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickEnd,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _pickupHours,
                  decoration: InputDecoration(
                    labelText: t('Délai pour retirer après la clôture'),
                  ),
                  items: [
                    for (final h in const [24, 48, 72, 168, 336])
                      DropdownMenuItem(
                        value: h,
                        child: Text(t('{n} h', {'n': h})),
                      ),
                  ],
                  onChanged: (v) => setState(() => _pickupHours = v ?? 72),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: Brand.green,
                  value: _publish,
                  onChanged: (v) => setState(() => _publish = v),
                  title: Text(t('Publier tout de suite')),
                  subtitle: Text(t('Une offre publiée ne se modifie plus.')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          BusyButton(
            key: const Key('save_offer'),
            label: t('Enregistrer l\'offre'),
            icon: Icons.check_circle_outline,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
