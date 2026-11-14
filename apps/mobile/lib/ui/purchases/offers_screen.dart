import 'package:flutter/material.dart';

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
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).purchases;
    final zoneId = (_zoneId ?? '').isEmpty ? null : _zoneId;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Achats groupés')),
        actions: [
          TextButton.icon(
            key: const Key('open_my_orders'),
            onPressed: () => _open(const MyOrdersScreen()),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(t('Mes commandes')),
          ),
        ],
      ),
      body: Loader<(List<PickupZone>, List<Offer>)>(
        key: ValueKey('$_version-$zoneId'),
        load: () async => (await api.zones(), await api.offers(zoneId: zoneId)),
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                t('Avec ton groupe, achète moins cher.'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                t('Réservez votre quantité. À la date de fin, le prix dépend du nombre d\'unités réservées. Vous payez et retirez en boutique.'),
                style: TextStyle(color: Brand.muted),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const Key('zone_all'),
                      label: Text(t('Toutes les zones')),
                      selected: zoneId == null,
                      onSelected: (_) => _chooseZone(null),
                    ),
                    for (final z in data.$1) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: Key('zone_${z.id}'),
                        label: Text(z.commune),
                        selected: zoneId == z.id,
                        onSelected: (_) => _chooseZone(z.id),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (data.$2.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    t('Aucune offre en cours ici pour le moment.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              for (final o in data.$2) OfferCard(offer: o, onTap: () => _open(OfferScreen(offerId: o.id))),
            ],
          ),
        ),
      ),
    );
  }
}
