import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return (
      offer,
      mine
          .where((o) => o.offerId == offer.id && o.status != 'cancelled')
          .firstOrNull,
    );
  }

  Future<void> _reserve(Offer offer) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => ReserveSheet(offer: offer),
    );
    if (done == true && mounted) {
      showInfo(
        context,
        t(
          'Réservation enregistrée. Vous paierez en boutique après la clôture.',
        ),
      );
      setState(() => _version++);
    }
  }

  Future<void> _invite(Offer offer) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => InviteSheet(offer: offer),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          t('Détail de l\'offre'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Brand.ink.withValues(alpha: 0.10),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
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

  Widget _details(
    BuildContext context,
    Offer o,
    Future<void> Function() reload,
  ) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        GradientHeader(
          underAppBar: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(o.title, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      o.unitLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${o.merchantName} · ${o.commune}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: OfferPrice(offer: o, large: true)),
                        TimeLeftPill(o.endsAt),
                      ],
                    ),
                    const SizedBox(height: 18),
                    OfferProgress(offer: o),
                  ],
                ),
              ),
              SectionCard(
                title: t('Prix selon les unités réservées'),
                icon: Icons.stairs_outlined,
                child: Column(
                  children: [
                    for (final tier in o.tiers) _TierRow(offer: o, tier: tier),
                  ],
                ),
              ),
              SectionCard(
                child: Column(
                  children: [
                    InfoRow(
                      t('Fin'),
                      formatDateTime(o.endsAt),
                      icon: Icons.schedule,
                    ),
                    const Divider(height: 20),
                    InfoRow(
                      t('Retrait et paiement'),
                      o.merchantAddress,
                      icon: Icons.storefront_outlined,
                    ),
                    const Divider(height: 20),
                    InfoRow(
                      t('Délai pour retirer'),
                      t('{n} h après la clôture', {'n': o.pickupWindowHours}),
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
              ),
              if (o.description != null) ...[
                const SizedBox(height: 16),
                Text(o.description!, style: const TextStyle(height: 1.4)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Brand.mint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 20,
                      color: Brand.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t(
                          'Sous le seuil à la date de fin, l\'offre est annulée et personne ne paie. Vous payez la boutique au retrait : Mchango ne touche pas à l\'argent.',
                        ),
                        style: TextStyle(
                          color: Brand.ink.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// Participer (ou ma réservation), et Inviter côte à côte.
  Widget _actions(BuildContext context, Offer o, PurchaseOrder? mine) {
    // Boutons simples : ils ouvrent une feuille, rien ne charge
    final tall = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)),
    );
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
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              key: const Key('my_reservation'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.bookmark_added, color: Brand.green),
              title: Text(
                t('Ma réservation : {n} {unit}', {
                  'n': mine.quantity,
                  'unit': o.unitLabel,
                }),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                orderStatusStyles[mine.status]?.label ?? mine.status,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MyOrdersScreen()),
              ),
            ),
          ),
          if (invite != null) ...[const SizedBox(height: 8), invite],
        ],
      );
    }
    if (!o.isOpen) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          t('Cette offre n\'accepte plus de réservation.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            key: const Key('participate'),
            style: tall,
            onPressed: () => _reserve(o),
            icon: const Icon(Icons.shopping_basket_outlined),
            label: Text(t('Participer')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: invite!),
      ],
    );
  }
}

/// Un palier de prix : coche verte quand il est atteint, mis en avant pour le palier en cours.
class _TierRow extends StatelessWidget {
  const _TierRow({required this.offer, required this.tier});

  final Offer offer;
  final OfferTier tier;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final reached = o.confirmedUnits >= tier.minQuantity;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: reached ? Brand.mint : Brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: reached
              ? Brand.green.withValues(alpha: 0.25)
              : Brand.ink.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            reached ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: reached ? Brand.green : Brand.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('À partir de {n}', {'n': tier.minQuantity}),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: reached ? Brand.ink : Brand.muted,
              ),
            ),
          ),
          Text(
            formatAmount(tier.unitPriceMinor, o.currency),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: reached ? Brand.green : Brand.ink,
            ),
          ),
        ],
      ),
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

  void _step(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _quantity += delta);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProductThumb(o.title, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('Participer'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${o.title} · ${o.unitLabel}',
                      style: TextStyle(color: Brand.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      key: const Key('qty_minus'),
                      iconSize: 26,
                      constraints: const BoxConstraints.tightFor(
                        width: 52,
                        height: 52,
                      ),
                      onPressed: _quantity > 1 ? () => _step(-1) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        '$_quantity',
                        key: const Key('qty_value'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Brand.green,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      key: const Key('qty_plus'),
                      iconSize: 26,
                      style: IconButton.styleFrom(backgroundColor: Brand.green),
                      constraints: const BoxConstraints.tightFor(
                        width: 52,
                        height: 52,
                      ),
                      onPressed: _quantity < 1000 ? () => _step(1) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  t('Total indicatif : {amount}', {
                    'amount': formatAmount(
                      _quantity * o.displayPriceMinor,
                      o.currency,
                    ),
                  }),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t('Le prix final dépend du palier atteint à la date de fin.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.muted, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('pickup_name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: t('Nom pour le retrait'),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          BusyButton(
            key: const Key('confirm_reservation'),
            label: t('Confirmer ma réservation'),
            icon: Icons.check_circle_outline,
            onPressed: _confirm,
          ),
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('Inviter'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              t('Aucun achat n\'est engagé par l\'envoi d\'une invitation.'),
              style: TextStyle(color: Brand.muted),
            ),
            const SizedBox(height: 14),
            Material(
              color: Brand.mint,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                key: const Key('share_whatsapp'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Brand.green,
                  child: Icon(
                    Icons.chat_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  t('Partager via WhatsApp'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _whatsApp(context),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              t('Proposer à un de mes groupes'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: Loader<List<Group>>(
                load: api.myGroups,
                builder: (context, groups, _) => groups.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          t('Vous n\'êtes encore dans aucun groupe.'),
                          style: TextStyle(color: Brand.muted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final g in groups)
                            ListTile(
                              key: Key('propose_${g.id}'),
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                backgroundColor: Brand.neutral,
                                child: Icon(
                                  Icons.groups_outlined,
                                  color: Brand.green,
                                ),
                              ),
                              title: Text(
                                g.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
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
