import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models.dart';
import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'my_orders_screen.dart';
import 'purchase_widgets.dart';

/// Fiche d'une offre : l'économie, le seuil, et deux gestes : Participer, Inviter.
class OfferScreen extends StatefulWidget {
  const OfferScreen({super.key, required this.offerId});

  final String offerId;

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  int _version = 0;

  Future<(Offer, PurchaseOrder?)> _load() async {
    final api = Services.of(context).purchases;
    final offer = await api.offer(widget.offerId);
    final mine = await api.myOrders();
    return (offer, mine.where((o) => o.offerId == offer.id && o.status != 'cancelled').firstOrNull);
  }

  Future<void> _reserve(Offer offer) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReserveSheet(offer: offer),
    );
    if (done == true && mounted) {
      showInfo(context, t('Réservation enregistrée. Vous paierez en boutique après la clôture.'));
      setState(() => _version++);
    }
  }

  Future<void> _invite(Offer offer) =>
      showModalBottomSheet<void>(context: context, builder: (_) => InviteSheet(offer: offer));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Détail de l\'offre'))),
      body: Loader<(Offer, PurchaseOrder?)>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final (o, mine) = data;
          // Les deux gestes restent visibles en bas de l'écran, même sur un petit téléphone
          return Column(
            children: [
              Expanded(child: _details(context, o, reload)),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Brand.ink.withValues(alpha: 0.08), blurRadius: 12)],
                  ),
                  child: _actions(context, o, mine),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context, Offer o, Future<void> Function() reload) => RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(o.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                Text(o.unitLabel, style: TextStyle(color: Brand.muted)),
                const SizedBox(height: 4),
                Text('${o.merchantName} · ${o.commune}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OfferPrice(offer: o, large: true),
                        const SizedBox(height: 16),
                        OfferProgress(offer: o),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Prix selon les unités réservées'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        for (final tier in o.tiers)
                          InfoRow(
                            t('À partir de {n}', {'n': tier.minQuantity}),
                            formatAmount(tier.unitPriceMinor, o.currency),
                            icon: o.confirmedUnits >= tier.minQuantity ? Icons.check_circle : Icons.radio_button_unchecked,
                          ),
                        const Divider(height: 24),
                        InfoRow(t('Fin'), formatDateTime(o.endsAt), icon: Icons.schedule),
                        InfoRow(t('Retrait et paiement'), o.merchantAddress, icon: Icons.storefront_outlined),
                        InfoRow(
                          t('Délai pour retirer'),
                          t('{n} h après la clôture', {'n': o.pickupWindowHours}),
                          icon: Icons.timer_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
                if (o.description != null) ...[
                  const SizedBox(height: 8),
                  Text(o.description!),
                ],
                const SizedBox(height: 8),
                Text(
                  t('Sous le seuil à la date de fin, l\'offre est annulée et personne ne paie. Vous payez la boutique au retrait : Mchango ne touche pas à l\'argent.'),
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          );

  /// Participer (ou ma réservation), et Inviter côte à côte.
  Widget _actions(BuildContext context, Offer o, PurchaseOrder? mine) {
    // Boutons simples : ils ouvrent une feuille, rien ne charge
    final tall = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)));
    final invite = o.isOpen
        ? OutlinedButton.icon(
            key: const Key('invite'),
            style: tall,
            onPressed: () => _invite(o),
            icon: const Icon(Icons.share),
            label: Text(t('Inviter')),
          )
        : null;
    if (mine != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Brand.mint,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: const Key('my_reservation'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.bookmark_added, color: Brand.green),
              title: Text(
                t('Ma réservation : {n} {unit}', {'n': mine.quantity, 'unit': o.unitLabel}),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(orderStatusStyles[mine.status]?.label ?? mine.status),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MyOrdersScreen())),
            ),
          ),
          if (invite != null) ...[const SizedBox(height: 8), invite],
        ],
      );
    }
    if (!o.isOpen) {
      return Text(
        t('Cette offre n\'accepte plus de réservation.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Brand.muted),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const Key('participate'),
            style: tall,
            onPressed: () => _reserve(o),
            icon: const Icon(Icons.shopping_basket_outlined),
            label: Text(t('Participer')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: invite!),
      ],
    );
  }
}

/// Choisir sa quantité et confirmer. L'identifiant hors ligne est créé une fois : renvoyer
/// après une coupure réseau ne crée pas de seconde commande.
class ReserveSheet extends StatefulWidget {
  const ReserveSheet({super.key, required this.offer});

  final Offer offer;

  @override
  State<ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends State<ReserveSheet> {
  final _offlineId = uuidV4();
  int _quantity = 1;
  late final _name = TextEditingController();
  bool _nameFilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameFilled) return;
    _nameFilled = true;
    _name.text = Services.of(context).auth.fullName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showInfo(context, t('Indiquez le nom pour le retrait.'));
      return;
    }
    await Services.of(context).purchases.reserve(
      offerId: widget.offer.id,
      quantity: _quantity,
      pickupName: name,
      offlineId: _offlineId,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('Participer'), style: Theme.of(context).textTheme.titleLarge),
          Text('${o.title} · ${o.unitLabel}', style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const Key('qty_minus'),
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '$_quantity',
                  key: const Key('qty_value'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                key: const Key('qty_plus'),
                onPressed: _quantity < 1000 ? () => setState(() => _quantity++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t('Total indicatif : {amount}', {'amount': formatAmount(_quantity * o.displayPriceMinor, o.currency)}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            t('Le prix final dépend du palier atteint à la date de fin.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pickup_name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: t('Nom pour le retrait')),
          ),
          const SizedBox(height: 16),
          BusyButton(key: const Key('confirm_reservation'), label: t('Confirmer ma réservation'), onPressed: _confirm),
        ],
      ),
    );
  }
}

/// Inviter : proposer à un de mes groupes, ou partager sur WhatsApp. Aucun achat n'est engagé.
class InviteSheet extends StatelessWidget {
  const InviteSheet({super.key, required this.offer});

  final Offer offer;

  static String shareText(Offer o) => t(
    '{title} ({unit}) à {price} au lieu de {regular} chez {shop}, {commune}. Réservez dans l\'app Mchango, rubrique Achats groupés, avant le {date}.',
    {
      'title': o.title,
      'unit': o.unitLabel,
      'price': formatAmount(o.displayPriceMinor, o.currency),
      'regular': formatAmount(o.regularPriceMinor, o.currency),
      'shop': o.merchantName,
      'commune': o.commune,
      'date': formatDateTime(o.endsAt),
    },
  );

  Future<void> _propose(BuildContext context, Group g) async {
    try {
      await Services.of(context).purchases.proposeToGroup(offer.id, g.id);
      if (context.mounted) {
        Navigator.pop(context);
        showInfo(context, t('Offre proposée à {group}.', {'group': g.name}));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _whatsApp(BuildContext context) async {
    try {
      // Le partage est enregistré (origine de l'invitation) avant d'ouvrir WhatsApp
      await Services.of(context).purchases.shareOnWhatsApp(offer.id);
      await SharePlus.instance.share(ShareParams(text: shareText(offer)));
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).api;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t('Inviter'), style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                t('Aucun achat n\'est engagé par l\'envoi d\'une invitation.'),
                style: TextStyle(color: Brand.muted),
              ),
            ),
            ListTile(
              key: const Key('share_whatsapp'),
              leading: const Icon(Icons.chat_outlined, color: Brand.green),
              title: Text(t('Partager via WhatsApp')),
              onTap: () => _whatsApp(context),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(t('Proposer à un de mes groupes'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Flexible(
              child: Loader<List<Group>>(
                load: api.myGroups,
                builder: (context, groups, _) => groups.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(t('Vous n\'êtes encore dans aucun groupe.'), style: TextStyle(color: Brand.muted)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final g in groups)
                            ListTile(
                              key: Key('propose_${g.id}'),
                              leading: const Icon(Icons.groups_outlined),
                              title: Text(g.name),
                              trailing: const Icon(Icons.send_outlined),
                              onTap: () => _propose(context, g),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
