import 'package:flutter/material.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../util/format.dart';
import '../theme.dart';

/// Statut d'une commande, vu par l'acheteur.
Map<String, StatusStyle> get orderStatusStyles => {
  'reserved': StatusStyle(t('Réservée'), Brand.goldDark, Icons.bookmark_added_outlined),
  'ready': StatusStyle(t('À payer et retirer'), Brand.green, Icons.storefront_outlined),
  'paid': StatusStyle(t('Payée : à retirer'), Brand.green, Icons.inventory_2_outlined),
  'picked_up': StatusStyle(t('Retirée'), Brand.success, Icons.check_circle),
  'cancelled': StatusStyle(t('Annulée'), Brand.muted, Icons.block),
  'expired': StatusStyle(t('Expirée'), Brand.danger, Icons.timer_off_outlined),
};

Map<String, String> get offerStatusLabels => {
  'draft': t('Brouillon'),
  'open': t('Ouverte'),
  'closed': t('Clôturée'),
  'cancelled': t('Annulée'),
  'fulfilled': t('Terminée'),
};

/// Prix collectif, prix habituel barré et réduction.
class OfferPrice extends StatelessWidget {
  const OfferPrice({super.key, required this.offer, this.large = false});

  final Offer offer;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          formatAmount(o.displayPriceMinor, o.currency),
          style: TextStyle(fontSize: large ? 28 : 20, fontWeight: FontWeight.w900, color: Brand.green),
        ),
        Text(
          formatAmount(o.regularPriceMinor, o.currency),
          style: TextStyle(color: Brand.muted, decoration: TextDecoration.lineThrough),
        ),
        if (o.discountPercent > 0)
          StatusPill('-${o.discountPercent} %', color: Brand.goldDark, background: Brand.goldLight),
      ],
    );
  }
}

/// Unités confirmées par rapport au seuil, et ce qui manque.
class OfferProgress extends StatelessWidget {
  const OfferProgress({super.key, required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final threshold = o.thresholdUnits == 0 ? 1 : o.thresholdUnits;
    final next = o.nextTier;
    final caption = o.missingUnits > 0
        ? t('{n} manquant(s) pour atteindre le prix collectif', {'n': o.missingUnits})
        : next == null
        ? t('Meilleur prix atteint')
        : t('Encore {n} pour passer à {price}', {
            'n': next.minQuantity - o.confirmedUnits,
            'price': formatAmount(next.unitPriceMinor, o.currency),
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('{n} / {threshold} {unit} confirmé(s)', {
            'n': o.confirmedUnits,
            'threshold': o.thresholdUnits,
            'unit': o.unitLabel,
          }),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (o.confirmedUnits / threshold).clamp(0, 1).toDouble(),
            minHeight: 10,
            backgroundColor: Brand.neutral,
            color: o.missingUnits > 0 ? Brand.gold : Brand.green,
          ),
        ),
        const SizedBox(height: 6),
        Text(caption, style: TextStyle(color: Brand.muted)),
      ],
    );
  }
}

/// Carte d'une offre dans une liste.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return Card(
      child: InkWell(
        key: Key('offer_${o.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(o.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text('${o.unitLabel} · ${o.merchantName}, ${o.commune}', style: TextStyle(color: Brand.muted)),
              const SizedBox(height: 10),
              OfferPrice(offer: o),
              const SizedBox(height: 10),
              OfferProgress(offer: o),
              const SizedBox(height: 6),
              Text(
                t('Fin : {date}', {'date': formatDateTime(o.endsAt)}),
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
