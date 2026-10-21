import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../groups/group_screen.dart';
import '../theme.dart';

/// Carnet personnel : ce que j'ai versé et reçu (paiements confirmés), mes prochaines étapes,
/// et le détail par tontine. Ce sont des montants constatés entre membres, pas un solde.
class CarnetScreen extends StatelessWidget {
  const CarnetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = Services.of(context).api;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon carnet')),
      body: Loader<Carnet>(
        load: api.carnet,
        builder: (context, c, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (c.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Votre carnet se remplira dès votre première tontine.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final t in c.totals) TotalsCard(total: t),
              if (c.upcoming.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('À venir', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final s in c.upcoming) StepTile(step: s),
              ],
              if (c.groups.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Par tontine', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final g in c.groups) _GroupLine(group: g),
              ],
              const SizedBox(height: 16),
              Text(
                'Montants des paiements confirmés par les bénéficiaires. $noCustodyNotice',
                style: TextStyle(color: Brand.ink.withValues(alpha: 0.6), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Versé et reçu dans une devise (les francs et les dollars ne s'additionnent pas).
class TotalsCard extends StatelessWidget {
  const TotalsCard({super.key, required this.total});

  final CarnetTotal total;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _Amount(
              icon: Icons.north_east,
              label: "J'ai versé",
              value: formatAmount(total.paidMinor, total.currency),
              color: Brand.ink,
            ),
          ),
          Container(width: 1, height: 44, color: Brand.ink.withValues(alpha: 0.08)),
          const SizedBox(width: 16),
          Expanded(
            child: _Amount(
              icon: Icons.south_west,
              label: "J'ai reçu",
              value: formatAmount(total.receivedMinor, total.currency),
              color: Brand.green,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Amount extends StatelessWidget {
  const _Amount({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: Brand.ink.withValues(alpha: 0.65))),
        ],
      ),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      ),
    ],
  );
}

/// Une prochaine étape : payer quelqu'un, ou recevoir à mon tour. Ouvre la tontine.
class StepTile extends StatelessWidget {
  const StepTile({super.key, required this.step});

  final CarnetStep step;

  @override
  Widget build(BuildContext context) {
    final s = step;
    final (icon, color, bg) = s.isPayment
        ? (s.late ? Icons.warning_amber_rounded : Icons.payments_outlined, s.late ? Colors.deepOrange : Brand.goldDark, const Color(0xFFFFF3D6))
        : (Icons.savings_outlined, Brand.green, Brand.mint);
    final title = s.isPayment
        ? 'Payer ${formatAmount(s.amountMinor, s.currency)} à ${s.counterpart}'
        : 'Mon tour : je reçois ${formatAmount(s.amountMinor, s.currency)}';
    final when = s.late ? 'en retard depuis le ${formatDate(s.dueDate)}' : 'le ${formatDate(s.dueDate)}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(backgroundColor: bg, foregroundColor: color, child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${s.groupName} · tour ${s.cycleNumber} · $when'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => GroupScreen(groupId: s.groupId)),
        ),
      ),
    );
  }
}

class _GroupLine extends StatelessWidget {
  const _GroupLine({required this.group});

  final CarnetGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final turn = g.myTurnCycle == null
        ? 'Tour pas encore fixé'
        : g.myTurnStatus == 'completed'
        ? 'Mon tour ${g.myTurnCycle} : reçu'
        : 'Mon tour : ${g.myTurnCycle}, le ${formatDate(g.myTurnDate!)}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(groupId: g.groupId))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(g.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  Text(groupStatusLabels[g.status] ?? g.status, style: TextStyle(color: Brand.ink.withValues(alpha: 0.6))),
                ],
              ),
              const SizedBox(height: 4),
              Text(turn, style: TextStyle(color: Brand.ink.withValues(alpha: 0.7))),
              const Divider(height: 20),
              InfoRow('Versé (${g.paidCount} paiement(s))', formatAmount(g.paidMinor, g.currency)),
              InfoRow('Reçu (${g.receivedCount} paiement(s))', formatAmount(g.receivedMinor, g.currency)),
              if (g.pendingCount > 0) InfoRow('En attente de confirmation', '${g.pendingCount}'),
            ],
          ),
        ),
      ),
    );
  }
}
