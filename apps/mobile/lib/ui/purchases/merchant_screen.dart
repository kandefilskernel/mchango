import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'create_offer_screen.dart';
import 'purchase_widgets.dart';

/// Espace boutique : au comptoir, retrouver une commande par son code, encaisser, remettre.
/// Et publier ses offres.
class MerchantScreen extends StatelessWidget {
  const MerchantScreen({super.key, required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Brand.green,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: Text(
            merchant.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Brand.gold,
            indicatorWeight: 3,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: [
              Tab(key: const Key('tab_counter'), text: t('Comptoir')),
              Tab(key: const Key('tab_offers'), text: t('Mes offres')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CounterTab(merchant: merchant),
            _OffersTab(merchant: merchant),
          ],
        ),
      ),
    );
  }
}

class _CounterTab extends StatefulWidget {
  const _CounterTab({required this.merchant});

  final Merchant merchant;

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  final _code = TextEditingController();
  int _version = 0;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _openOrder(MerchantOrder order) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _CounterSheet(
        merchantId: widget.merchant.id,
        order: order,
        typedCode: _code.text.trim(),
      ),
    );
    if (changed == true && mounted) {
      _code.clear();
      setState(() => _version++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).purchases;
    return Loader<List<MerchantOrder>>(
      key: ValueKey(_version),
      load: () => api.merchantOrders(widget.merchant.id),
      builder: (context, orders, reload) => ListenableBuilder(
        listenable: _code,
        builder: (context, _) {
          final typed = _code.text.trim().toUpperCase();
          final shown = typed.isEmpty
              ? orders
              : orders
                    .where(
                      (o) =>
                          o.pickupCode.toUpperCase().contains(typed) ||
                          o.pickupName.toUpperCase().contains(typed),
                    )
                    .toList();
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                TextField(
                  key: const Key('counter_code'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('Code de retrait ou nom du client'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  t("Commandes à encaisser ou à remettre : {n}", {
                    'n': orders.length,
                  }),
                  style: TextStyle(color: Brand.muted),
                ),
                const SizedBox(height: 8),
                for (final o in shown)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Brand.ink.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: Key('counter_${o.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: ProductThumb(o.title, size: 46),
                        title: Text(
                          '${o.pickupCode} · ${o.pickupName}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${o.title} · ${o.quantity} ${o.unitLabel} · ${formatAmount(o.amountDueMinor, o.currency)}',
                        ),
                        trailing: StatusPill(
                          o.status == 'paid' ? t('Payée') : t('À encaisser'),
                          color: o.status == 'paid'
                              ? Brand.green
                              : Brand.goldDark,
                          background: o.status == 'paid'
                              ? Brand.mint
                              : Brand.goldLight,
                        ),
                        onTap: () => _openOrder(o),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Une commande au comptoir : encaisser (espèces ou mobile money), puis remettre le produit
/// contre le code que montre le client.
class _CounterSheet extends StatefulWidget {
  const _CounterSheet({
    required this.merchantId,
    required this.order,
    required this.typedCode,
  });

  final String merchantId;
  final MerchantOrder order;
  final String typedCode;

  @override
  State<_CounterSheet> createState() => _CounterSheetState();
}

class _CounterSheetState extends State<_CounterSheet> {
  late MerchantOrder _order = widget.order;
  String _method = 'cash';
  final _txRef = TextEditingController();
  late final _code = TextEditingController(text: widget.typedCode);

  @override
  void dispose() {
    _txRef.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final ref = _txRef.text.trim();
    if (_method != 'cash' && ref.isEmpty) {
      showInfo(context, t('Saisissez le numéro de la transaction du mobile money.'));
      return;
    }
    final updated = await Services.of(context).purchases.confirmPayment(
      widget.merchantId,
      _order.id,
      method: _method,
      txReference: _method == 'cash' ? null : ref,
    );
    setState(() => _order = updated);
  }

  Future<void> _handOver() async {
    await Services.of(context).purchases
        .confirmPickup(widget.merchantId, _order.id, _code.text.trim());
    if (mounted) {
      Navigator.pop(context, true);
      showInfo(context, t('Produit remis. Merci !'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, o.status != widget.order.status);
      },
      child: SingleChildScrollView(
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
                        o.pickupName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${o.title} · ${o.quantity} ${o.unitLabel}',
                        style: TextStyle(color: Brand.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Brand.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: InfoRow(
                t('Montant'),
                formatAmount(o.amountDueMinor, o.currency),
                icon: Icons.payments_outlined,
              ),
            ),
            if (o.status == 'ready') ...[
              if (o.paymentStatus == 'declared')
                Text(
                  t('Le client dit avoir payé : vérifiez avant de confirmer.'),
                  style: const TextStyle(
                    color: Brand.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('counter_method'),
                initialValue: _method,
                decoration: InputDecoration(labelText: t('Moyen de paiement')),
                items: [
                  for (final e in methodLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
              if (_method != 'cash') ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('counter_txref'),
                  controller: _txRef,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: t('Numéro de la transaction'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              BusyButton(
                key: const Key('confirm_payment'),
                label: t('J\'ai reçu {amount}', {
                  'amount': formatAmount(o.amountDueMinor, o.currency),
                }),
                icon: Icons.check,
                onPressed: _pay,
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Brand.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t('Paiement confirmé.'),
                    style: const TextStyle(
                      color: Brand.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('handover_code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: t('Code montré par le client'),
                ),
              ),
              const SizedBox(height: 16),
              BusyButton(
                key: const Key('confirm_pickup'),
                label: t('Remettre le produit'),
                icon: Icons.inventory_2_outlined,
                onPressed: _handOver,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OffersTab extends StatefulWidget {
  const _OffersTab({required this.merchant});

  final Merchant merchant;

  @override
  State<_OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends State<_OffersTab> {
  int _version = 0;

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateOfferScreen(merchantId: widget.merchant.id),
      ),
    );
    if (created == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).purchases;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_offer'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(t('Nouvelle offre')),
      ),
      body: Loader<List<Offer>>(
        key: ValueKey(_version),
        load: () => api.merchantOffers(widget.merchant.id),
        builder: (context, offers, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (offers.isEmpty)
                EmptyState(
                  icon: Icons.local_offer_outlined,
                  title: t(
                    'Aucune offre. Créez la première : prix habituel, paliers, date de fin.',
                  ),
                ),
              for (final o in offers)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Brand.ink.withValues(alpha: 0.07),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ProductThumb(o.title, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${o.title} · ${o.unitLabel}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            StatusPill(
                              offerStatusLabels[o.status] ?? o.status,
                              color: o.status == 'open'
                                  ? Brand.green
                                  : Brand.ink,
                              background: o.status == 'open'
                                  ? Brand.mint
                                  : Brand.neutral,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OfferProgress(offer: o),
                        if (o.status == 'draft') ...[
                          const SizedBox(height: 12),
                          BusyButton(
                            key: Key('publish_${o.id}'),
                            label: t('Publier'),
                            onPressed: () async {
                              await api.publishOffer(widget.merchant.id, o.id);
                              await reload();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
