import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'offer_screen.dart';
import 'purchase_widgets.dart';

/// Offres proposées dans un groupe. Chacun décide pour lui-même : on montre combien de
/// membres ont réservé, jamais la liste de ceux qui n'ont pas répondu.
class GroupProposalsScreen extends StatelessWidget {
  const GroupProposalsScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          t('Achats proposés'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Loader<List<GroupProposal>>(
        load: () => Services.of(context).purchases.groupProposals(groupId),
        builder: (context, proposals, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              GradientHeader(
                underAppBar: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                child: Row(
                  children: [
                    const Icon(Icons.groups_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  children: [
                    if (proposals.isEmpty)
                      EmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: t(
                          'Aucun achat proposé. Depuis une offre, touchez « Inviter » pour la proposer ici.',
                        ),
                      ),
                    for (final p in proposals) _ProposalCard(p, reload),
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

class _ProposalCard extends StatelessWidget {
  const _ProposalCard(this.p, this.reload);

  final GroupProposal p;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
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
          key: Key('proposal_${p.offerId}'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => OfferScreen(offerId: p.offerId),
            ),
          ).then((_) => reload()),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProductThumb(p.title, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${p.title} · ${p.unitLabel}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            t('Proposé par {name}', {'name': p.proposedByName}),
                            style: TextStyle(color: Brand.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                const SizedBox(height: 12),
                StatusPill(
                  t('{n} membre(s) du groupe ont réservé', {
                    'n': p.confirmedMembers,
                  }),
                  icon: Icons.group_outlined,
                  color: Brand.green,
                  background: Brand.mint,
                ),
                const SizedBox(height: 8),
                Text(
                  t('{n} / {threshold} confirmé(s) · fin le {date}', {
                    'n': p.confirmedUnits,
                    'threshold': p.thresholdUnits,
                    'date': formatDateTime(p.endsAt),
                  }),
                  style: TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
