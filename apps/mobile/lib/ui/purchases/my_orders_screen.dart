import 'package:flutter/material.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'purchase_widgets.dart';

/// Mes commandes : statut, montant, et le code à montrer en boutique.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  int _version = 0;

  Future<void> _cancel(PurchaseOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Annuler cette réservation ?')),
        content: Text(t('Vous pourrez réserver à nouveau tant que l\'offre est ouverte.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Non'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Annuler la réservation'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Services.of(context).purchases.cancelOrder(order.id);
      if (mounted) setState(() => _version++);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Mes commandes'))),
      body: Loader<List<PurchaseOrder>>(
        key: ValueKey(_version),
        load: Services.of(context).purchases.myOrders,
        builder: (context, orders, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (orders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    t('Aucune commande pour le moment.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              for (final o in orders) _OrderCard(order: o, onCancel: () => _cancel(o)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onCancel});

  final PurchaseOrder order;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final style = orderStatusStyles[o.status];
    final amount = o.amountDueMinor != null
        ? t('À payer en boutique : {amount}', {'amount': formatAmount(o.amountDueMinor!, o.currency)})
        : o.indicativeTotalMinor != null
        ? t('Total indicatif : {amount}', {'amount': formatAmount(o.indicativeTotalMinor!, o.currency)})
        : t('Prix collectif pas encore atteint');
    return Card(
      key: Key('order_${o.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.title} · ${o.quantity} ${o.unitLabel}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (style != null) StatusPill(style.label, color: style.color, icon: style.icon),
              ],
            ),
            const SizedBox(height: 4),
            Text('${o.merchantName} · ${o.merchantAddress}', style: TextStyle(color: Brand.muted)),
            const SizedBox(height: 8),
            if (o.isActive && o.status != 'picked_up') Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (o.pickupCode != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text(t('Code de retrait'), style: TextStyle(color: Brand.muted)),
                    Text(
                      o.pickupCode!,
                      key: const Key('pickup_code'),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 3, color: Brand.green),
                    ),
                    Text(
                      t('Au nom de {name}', {'name': o.pickupName}),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (o.pickupDeadline != null) ...[
                const SizedBox(height: 6),
                Text(
                  t('À retirer avant le {date}', {'date': formatDateTime(o.pickupDeadline!)}),
                  style: TextStyle(color: Brand.muted),
                ),
              ],
            ],
            if (o.status == 'reserved')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  t('Clôture le {date}. Le code de retrait arrive à ce moment-là.', {'date': formatDateTime(o.endsAt)}),
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ),
            if (o.canChange)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('cancel_${o.id}'),
                  onPressed: onCancel,
                  child: Text(t('Annuler la réservation')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
