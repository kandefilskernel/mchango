import 'package:flutter/material.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'offer_screen.dart';

/// Offres proposées dans un groupe. Chacun décide pour lui-même : on montre combien de
/// membres ont réservé, jamais la liste de ceux qui n'ont pas répondu.
class GroupProposalsScreen extends StatelessWidget {
  const GroupProposalsScreen({super.key, required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Achats proposés'))),
      body: Loader<List<GroupProposal>>(
        load: () => Services.of(context).purchases.groupProposals(groupId),
        builder: (context, proposals, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(groupName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (proposals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    t('Aucun achat proposé. Depuis une offre, touchez « Inviter » pour la proposer ici.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.muted),
                  ),
                ),
              for (final p in proposals)
                Card(
                  child: ListTile(
                    key: Key('proposal_${p.offerId}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text('${p.title} · ${p.unitLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Proposé par {name}', {'name': p.proposedByName})),
                        Text(
                          t('{n} membre(s) du groupe ont réservé', {'n': p.confirmedMembers}),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.green),
                        ),
                        Text(
                          t('{n} / {threshold} confirmé(s) · fin le {date}', {
                            'n': p.confirmedUnits,
                            'threshold': p.thresholdUnits,
                            'date': formatDateTime(p.endsAt),
                          }),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => OfferScreen(offerId: p.offerId)),
                    ).then((_) => reload()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
