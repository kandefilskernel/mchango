import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../common.dart';
import '../theme.dart';
import 'my_orders_screen.dart';
import 'offer_screen.dart';
import 'purchase_widgets.dart';

/// Offres en cours près de chez moi : « Avec ton groupe, achète moins cher. »
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  /// Zone choisie, gardée sur le téléphone.
  static const zoneKey = 'purchase_zone';

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  String? _zoneId;
  bool _zoneLoaded = false;
  int _version = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_zoneLoaded) return;
    _zoneLoaded = true;
    Services.of(context).store.read(OffersScreen.zoneKey).then((z) {
      if (mounted && z != null) setState(() => _zoneId = z);
    });
  }

  Future<void> _chooseZone(String? zoneId) async {
    final store = Services.of(context).store;
    setState(() => _zoneId = zoneId);
    await store.write(OffersScreen.zoneKey, zoneId ?? '');
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).purchases;
    final zoneId = (_zoneId ?? '').isEmpty ? null : _zoneId;
    return Scaffold(
      // Barre verte qui se prolonge dans l'en-tête en dégradé
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          t('Achats groupés'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              key: const Key('open_my_orders'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => _open(const MyOrdersScreen()),
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: Text(t('Mes commandes')),
            ),
          ),
        ],
      ),
      body: Loader<(List<PickupZone>, List<Offer>)>(
        key: ValueKey('$_version-$zoneId'),
        load: () async => (await api.zones(), await api.offers(zoneId: zoneId)),
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientHeader(
                underAppBar: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Avec ton groupe, achète moins cher.'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Réservez votre quantité. À la date de fin, le prix dépend du nombre d\'unités réservées. Vous payez et retirez en boutique.',
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    _ZoneChip(
                      key: const Key('zone_all'),
                      label: t('Toutes les zones'),
                      selected: zoneId == null,
                      onTap: () => _chooseZone(null),
                    ),
                    for (final z in data.$1) ...[
                      const SizedBox(width: 8),
                      _ZoneChip(
                        key: Key('zone_${z.id}'),
                        label: z.commune,
                        selected: zoneId == z.id,
                        onTap: () => _chooseZone(z.id),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  children: [
                    if (data.$2.isEmpty)
                      EmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: t('Aucune offre en cours ici pour le moment.'),
                      ),
                    for (final o in data.$2)
                      OfferCard(
                        offer: o,
                        onTap: () => _open(OfferScreen(offerId: o.id)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zone de retrait : pastille sélectionnable, pleine quand elle est choisie.
class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    avatar: selected
        ? const Icon(Icons.place, size: 16, color: Colors.white)
        : null,
    labelStyle: TextStyle(
      fontWeight: FontWeight.w700,
      color: selected ? Colors.white : Brand.ink,
    ),
    selectedColor: Brand.green,
    backgroundColor: Colors.white,
    side: BorderSide(
      color: selected ? Brand.green : Brand.ink.withValues(alpha: 0.12),
    ),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
  );
}
