import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        content: Text(
          t('Vous pourrez réserver à nouveau tant que l\'offre est ouverte.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Non')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Annuler la réservation')),
          ),
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
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          t('Mes commandes'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Loader<List<PurchaseOrder>>(
        key: ValueKey(_version),
        load: Services.of(context).purchases.myOrders,
        builder: (context, orders, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (orders.isEmpty)
                EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: t('Aucune commande pour le moment.'),
                ),
              for (final o in orders)
                _OrderCard(order: o, onCancel: () => _cancel(o)),
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
        ? t('À payer en boutique : {amount}', {
            'amount': formatAmount(o.amountDueMinor!, o.currency),
          })
        : o.indicativeTotalMinor != null
        ? t('Total indicatif : {amount}', {
            'amount': formatAmount(o.indicativeTotalMinor!, o.currency),
          })
        : t('Prix collectif pas encore atteint');
    return Container(
      key: Key('order_${o.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(o.title, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${o.title} · ${o.quantity} ${o.unitLabel}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${o.merchantName} · ${o.merchantAddress}',
                      style: TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (style != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                style.label,
                color: style.color,
                icon: style.icon,
                background: style.color == Brand.muted
                    ? Brand.neutral
                    : style.color.withValues(alpha: 0.12),
              ),
            ),
          ],
          if (o.isActive && o.status != 'picked_up') ...[
            const SizedBox(height: 10),
            Text(
              amount,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ],
          if (o.pickupCode != null) ...[
            const SizedBox(height: 14),
            _PickupTicket(order: o),
            if (o.pickupDeadline != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: Brand.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      t('À retirer avant le {date}', {
                        'date': formatDateTime(o.pickupDeadline!),
                      }),
                      style: TextStyle(color: Brand.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ],
          if (o.status == 'reserved')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t(
                  'Clôture le {date}. Le code de retrait arrive à ce moment-là.',
                  {'date': formatDateTime(o.endsAt)},
                ),
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ),
          if (o.canChange)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('cancel_${o.id}'),
                style: TextButton.styleFrom(foregroundColor: Brand.danger),
                onPressed: onCancel,
                child: Text(t('Annuler la réservation')),
              ),
            ),
        ],
      ),
    );
  }
}

/// Le code à montrer en boutique : grand, lisible de loin, avec le nom du retrait.
class _PickupTicket extends StatelessWidget {
  const _PickupTicket({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Brand.mint, Color(0xFFCFE8DB)],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Brand.green.withValues(alpha: 0.2)),
    ),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 18, color: Brand.green),
            const SizedBox(width: 6),
            Text(
              t('Code de retrait'),
              style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          order.pickupCode!,
          key: const Key('pickup_code'),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            color: Brand.green,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          t('Au nom de {name}', {'name': order.pickupName}),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
