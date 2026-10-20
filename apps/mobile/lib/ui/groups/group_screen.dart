import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../cycles/cycle_screen.dart';
import '../history/history_screen.dart';
import 'turn_order_screen.dart';

class _GroupData {
  _GroupData(this.group, this.board);
  final Group group;
  final Board? board;
}

class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  int _version = 0;

  Future<_GroupData> _load() async {
    final api = Services.of(context).api;
    final group = await api.group(widget.groupId);
    return _GroupData(group, group.isDraft ? null : await api.board(widget.groupId));
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tontine'),
        actions: [
          IconButton(
            tooltip: 'Historique vérifié',
            icon: const Icon(Icons.history),
            onPressed: () => _push(HistoryScreen(groupId: widget.groupId)),
          ),
        ],
      ),
      body: Loader<_GroupData>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _Header(group: data.group),
            const SizedBox(height: 16),
            if (data.group.isDraft)
              ..._draftSection(context, data.group, reload)
            else
              ..._boardSection(context, data.group, data.board!),
          ]),
        ),
      ),
    );
  }

  List<Widget> _draftSection(BuildContext context, Group g, Future<void> Function() reload) {
    final api = Services.of(context).api;
    return [
      Text('Membres (${g.members.length}/${g.maxMembers})', style: Theme.of(context).textTheme.titleMedium),
      for (final m in g.members)
        ListTile(
          leading: CircleAvatar(child: Text(m.turnOrder?.toString() ?? '–')),
          title: Text(m.fullName),
          subtitle: Text(m.role == 'president' ? 'Président(e) · ${m.phone}' : m.phone),
        ),
      _OrderInfo(group: g),
      const SizedBox(height: 16),
      if (!g.isPresident)
        const Text('En attente du démarrage par le président.', textAlign: TextAlign.center)
      else ...[
        BusyButton(
          label: 'Inviter des membres',
          icon: Icons.share,
          onPressed: () async {
            final invitation = await api.createInvitation(g.id);
            if (context.mounted) await _showInvitation(context, invitation);
          },
        ),
        const SizedBox(height: 12),
        BusyButton(
          label: 'Ordre des tours',
          icon: Icons.format_list_numbered,
          outlined: true,
          onPressed: g.members.length < 2 ? null : () => _push(TurnOrderScreen(group: g)),
        ),
        const SizedBox(height: 12),
        BusyButton(
          label: 'Démarrer la tontine',
          icon: Icons.play_arrow,
          onPressed: g.hasCompleteOrder
              ? () async {
                  if (await _confirmStart(context, g) != true) return;
                  await api.start(g.id);
                  await reload();
                }
              : null,
        ),
        if (!g.hasCompleteOrder)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text("Pour démarrer : au moins 2 membres et l'ordre des tours fixé.",
                textAlign: TextAlign.center),
          ),
      ],
    ];
  }

  List<Widget> _boardSection(BuildContext context, Group g, Board board) => [
        Text('Tableau des tours', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final c in board.cycles)
          Card(
            color: c.status == 'open' ? Theme.of(context).colorScheme.primaryContainer : null,
            child: ListTile(
              leading: CircleAvatar(
                child: c.status == 'completed' ? const Icon(Icons.check) : Text('${c.cycleNumber}'),
              ),
              title: Text(c.beneficiaryMembershipId == board.myMembershipId
                  ? 'Tour ${c.cycleNumber} : vous recevez'
                  : 'Tour ${c.cycleNumber} : ${c.beneficiaryName}'),
              subtitle: Text('${formatDate(c.dueDate)} · ${cycleStatusLabels[c.status]} · '
                  '${c.confirmedCount}/${c.expectedCount} confirmé(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _push(CycleScreen(group: g, cycleNumber: c.cycleNumber)),
            ),
          ),
        _OrderInfo(group: g),
      ];

  Future<void> _showInvitation(BuildContext context, Invitation invitation) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Code d'invitation"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(invitation.code,
                style: const TextStyle(fontSize: 32, letterSpacing: 4, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Valable jusqu\'au ${formatDateTime(invitation.expiresAt)}'),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invitation.code));
                if (context.mounted) showInfo(context, 'Code copié.');
              },
              child: const Text('Copier'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Partager'),
              onPressed: () => SharePlus.instance.share(ShareParams(text: invitation.shareText)),
            ),
          ],
        ),
      );

  Future<bool?> _confirmStart(BuildContext context, Group g) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Démarrer la tontine ?'),
          content: Text('${g.members.length} tours seront créés à partir du ${formatDate(g.startDate)}. '
              "Ensuite, l'ordre, le montant et la liste des membres ne pourront plus changer."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Démarrer')),
          ],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(group.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            InfoRow('Cotisation par tour', formatAmount(group.contributionAmountMinor, group.currency),
                icon: Icons.payments_outlined),
            InfoRow('Fréquence', frequencyLabels[group.frequency] ?? group.frequency, icon: Icons.repeat),
            InfoRow('Premier tour', formatDate(group.startDate), icon: Icons.event),
            InfoRow('Statut', groupStatusLabels[group.status] ?? group.status, icon: Icons.flag_outlined),
          ]),
        ),
      );
}

/// Comment l'ordre a été fixé : la transparence passe aussi par là.
class _OrderInfo extends StatelessWidget {
  const _OrderInfo({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final seed = group.drawSeed;
    final text = switch (group.turnOrderMode) {
      'draw' => 'Ordre tiré au sort. Graine publique : ${seed!.substring(0, 16)}…',
      'chosen' when seed != null =>
        'Ordre choisi par le président (un tirage au sort avait eu lieu avant).',
      'chosen' => 'Ordre choisi par le président.',
      _ => "Ordre des tours pas encore fixé.",
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
