import 'package:flutter/material.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../util/format.dart';
import '../theme.dart';

/// Statut d'une commande, vu par l'acheteur.
Map<String, StatusStyle> get orderStatusStyles => {
  'reserved': StatusStyle(
    t('Réservée'),
    Brand.goldDark,
    Icons.bookmark_added_outlined,
  ),
  'ready': StatusStyle(
    t('À payer et retirer'),
    Brand.green,
    Icons.storefront_outlined,
  ),
  'paid': StatusStyle(
    t('Payée : à retirer'),
    Brand.green,
    Icons.inventory_2_outlined,
  ),
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

/// Vignette du produit : initiale sur fond dégradé (pas de photo requise).
class ProductThumb extends StatelessWidget {
  const ProductThumb(this.title, {super.key, this.size = 56});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = title.trim().isEmpty
        ? '·'
        : title.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.mint, Color(0xFFC9E5D6)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      // Décoratif : le nom du produit est déjà lu à côté
      child: ExcludeSemantics(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: size * 0.46,
            fontWeight: FontWeight.w900,
            color: Brand.green,
          ),
        ),
      ),
    );
  }
}

/// Temps restant avant la fin : « 3 j 4 h », « 5 h 20 », « < 1 h ».
String timeLeft(DateTime endsAt) {
  final d = endsAt.difference(DateTime.now());
  if (d.inMinutes < 60) return d.isNegative ? '0' : '< 1 h';
  if (d.inHours < 24)
    return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  return '${d.inDays} j ${d.inHours % 24} h';
}

/// Pastille « il reste X » : dorée, rouge quand il reste moins d'un jour.
class TimeLeftPill extends StatelessWidget {
  const TimeLeftPill(this.endsAt, {super.key});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final urgent = endsAt.difference(DateTime.now()).inHours < 24;
    return StatusPill(
      timeLeft(endsAt),
      icon: Icons.schedule_rounded,
      color: urgent ? Brand.danger : Brand.goldDark,
      background: urgent ? Brand.dangerBg : Brand.goldLight,
    );
  }
}

/// Bloc blanc arrondi avec un titre de section facultatif.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.icon, required this.child});

  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Brand.ink.withValues(alpha: 0.06)),
      boxShadow: [
        BoxShadow(
          color: Brand.ink.withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Brand.green),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // Les ListTile peignent leur fond sur le Material le plus proche
        Material(type: MaterialType.transparency, child: child),
      ],
    ),
  );
}

/// État vide : pastille d'icône, titre, explication.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Brand.mint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: Brand.green),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted),
          ),
        ],
      ],
    ),
  );
}

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
          style: TextStyle(
            fontSize: large ? 32 : 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: Brand.green,
          ),
        ),
        Text(
          formatAmount(o.regularPriceMinor, o.currency),
          style: TextStyle(
            color: Brand.muted,
            fontSize: large ? 16 : 14,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        if (o.discountPercent > 0)
          StatusPill(
            '-${o.discountPercent} %',
            color: Brand.goldDark,
            background: Brand.goldLight,
          ),
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
    final reached = o.missingUnits == 0;
    final next = o.nextTier;
    final caption = o.missingUnits > 0
        ? t("Encore {n} pour avoir le prix du groupe", {
            'n': o.missingUnits,
          })
        : next == null
        ? t('Meilleur prix atteint')
        : t('Encore {n} pour passer à {price}', {
            'n': next.minQuantity - o.confirmedUnits,
            'price': formatAmount(next.unitPriceMinor, o.currency),
          });
    final accent = reached ? Brand.green : Brand.goldDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t("Réservé : {n} sur {threshold} {unit}", {
            'n': o.confirmedUnits,
            'threshold': o.thresholdUnits,
            'unit': o.unitLabel,
          }),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              end: (o.confirmedUnits / threshold).clamp(0, 1).toDouble(),
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 10,
              backgroundColor: Brand.neutral,
              color: reached ? Brand.greenLight : Brand.gold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              reached ? Icons.check_circle_rounded : Icons.trending_up_rounded,
              size: 16,
              color: accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                caption,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Brand.ink.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('offer_${o.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductThumb(o.title),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            o.unitLabel,
                            style: TextStyle(
                              color: Brand.muted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.storefront_outlined,
                                size: 14,
                                color: Brand.muted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${o.merchantName}, ${o.commune}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Brand.muted,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TimeLeftPill(o.endsAt),
                  ],
                ),
                const SizedBox(height: 14),
                OfferPrice(offer: o),
                const SizedBox(height: 14),
                OfferProgress(offer: o),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
