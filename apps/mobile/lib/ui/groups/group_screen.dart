import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../cycles/cycle_screen.dart';
import '../history/history_screen.dart';
import '../purchases/group_proposals_screen.dart';
import '../theme.dart';
import 'terms_section.dart';
import 'turn_order_screen.dart';
import '../../l10n/l10n.dart';

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

  /// Nom du groupe, une fois chargé (titre de l'écran des achats proposés).
  String? _groupName;

  Future<_GroupData> _load() async {
    final api = Services.of(context).api;
    final group = await api.group(widget.groupId);
    _groupName = group.name;
    return _GroupData(group, group.isDraft ? null : await api.board(widget.groupId));
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barre verte qui se prolonge dans l'en-tête en dégradé
      appBar: AppBar(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          IconButton(
            key: const Key('open_proposals'),
            tooltip: t('Achats proposés'),
            icon: const Icon(Icons.shopping_basket_outlined),
            onPressed: () => _push(GroupProposalsScreen(groupId: widget.groupId, groupName: _groupName ?? '')),
          ),
          IconButton(
            tooltip: t('Historique vérifié'),
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
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Header(group: data.group),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: data.group.isDraft
                      ? _draftSection(context, data.group, reload)
                      : _boardSection(context, data.group, data.board!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _draftSection(BuildContext context, Group g, Future<void> Function() reload) {
    final api = Services.of(context).api;
    final terms = g.terms;
    final ready = g.hasCompleteOrder && (terms?.allSigned ?? false);
    return [
      _SectionTitle(t('Membres ({n}/{max})', {'n': g.members.length, 'max': g.maxMembers})),
      Card(
        child: Column(
          children: [
            for (final m in g.members)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Brand.mint,
                  foregroundColor: Brand.green,
                  child: Text(m.turnOrder?.toString() ?? '–', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(m.role == 'president' ? t('Président(e) · {phone}', {'phone': m.phone}) : m.phone),
              ),
          ],
        ),
      ),
      _OrderInfo(group: g),
      const SizedBox(height: 16),
      TermsSection(group: g, onSigned: reload),
      const SizedBox(height: 16),
      _StartChecklist(group: g),
      const SizedBox(height: 16),
      if (!g.isPresident)
        Text(
          t('En attente du démarrage par le président.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.muted),
        )
      else ...[
        BusyButton(
          label: t('Démarrer la tontine'),
          icon: Icons.play_arrow,
          onPressed: ready
              ? () async {
                  if (await _confirmStart(context, g) != true) return;
                  await api.start(g.id);
                  await reload();
                }
              : null,
        ),
        if (!g.hasCompleteOrder)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t("Pour démarrer : au moins 2 membres et l'ordre des tours fixé."),
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted),
            ),
          )
        else if (terms != null && !terms.allSigned)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              t('En attente des signatures : {names}', {'names': terms.missing.join(', ')}),
              key: const Key('missing_signatures'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.muted),
            ),
          ),
        const SizedBox(height: 12),
        BusyButton(
          label: t('Inviter des membres'),
          icon: Icons.share,
          outlined: true,
          onPressed: () async {
            final invitation = await api.createInvitation(g.id);
            if (context.mounted) await _showInvitation(context, invitation);
          },
        ),
        const SizedBox(height: 12),
        BusyButton(
          label: t('Ordre des tours'),
          icon: Icons.format_list_numbered,
          outlined: true,
          onPressed: g.members.length < 2 ? null : () => _push(TurnOrderScreen(group: g)),
        ),
      ],
    ];
  }

  List<Widget> _boardSection(BuildContext context, Group g, Board board) {
    CycleSummary? current;
    for (final c in board.cycles) {
      if (c.status == 'open') {
        current = c;
        break;
      }
    }
    String titleOf(CycleSummary c) => c.beneficiaryMembershipId == board.myMembershipId
        ? t('Tour {n} : vous recevez', {'n': c.cycleNumber})
        : t('Tour {n} : {name}', {'n': c.cycleNumber, 'name': c.beneficiaryName});
    final open = current;
    return [
      if (open != null) ...[
        _CurrentCycleCard(
          title: titleOf(open),
          cycle: open,
          mine: open.beneficiaryMembershipId == board.myMembershipId,
          onOpen: () => _push(CycleScreen(group: g, cycleNumber: open.cycleNumber)),
        ),
        const SizedBox(height: 20),
      ],
      _SectionTitle(t('Tableau des tours')),
      for (final c in board.cycles)
        _CycleTile(
          title: titleOf(c),
          cycle: c,
          mine: c.beneficiaryMembershipId == board.myMembershipId,
          onTap: () => _push(CycleScreen(group: g, cycleNumber: c.cycleNumber)),
        ),
      _OrderInfo(group: g),
    ];
  }

  Future<void> _showInvitation(BuildContext context, Invitation invitation) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t("Code d'invitation")),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(14)),
            child: SelectableText(
              invitation.code,
              style: const TextStyle(fontSize: 32, letterSpacing: 4, fontWeight: FontWeight.w800, color: Brand.green),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('Valable jusqu\'au {date}', {'date': formatDateTime(invitation.expiresAt)}),
            style: TextStyle(color: Brand.muted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: invitation.code));
            if (context.mounted) showInfo(context, t('Code copié.'));
          },
          child: Text(t('Copier')),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.share),
          label: Text(t('Partager')),
          onPressed: () => SharePlus.instance.share(ShareParams(text: invitation.shareText)),
        ),
      ],
    ),
  );

  Future<bool?> _confirmStart(BuildContext context, Group g) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('Démarrer la tontine ?')),
      content: Text(
        t(
          "{n} tours seront créés à partir du {date}. Ensuite, l'ordre, le montant et la liste des membres ne pourront plus changer.",
          {'n': g.members.length, 'date': formatDate(g.startDate)},
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, true),
          child: Text(t('Démarrer')),
        ),
      ],
    ),
  );
}

/// Nom, montant, fréquence et statut, sur le même dégradé que l'accueil.
class _Header extends StatelessWidget {
  const _Header({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final (color, bg) = switch (g.status) {
      'active' => (Brand.green, Brand.mint),
      'closed' => (Brand.muted, Brand.neutral),
      'suspended' => (Brand.danger, Brand.dangerBg),
      _ => (Brand.goldDark, Brand.goldLight),
    };
    final soft = Colors.white.withValues(alpha: 0.85);
    return GradientHeader(
      underAppBar: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.name,
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 6),
          Text(
            '${formatAmount(g.contributionAmountMinor, g.currency)} · ${frequencyLabels[g.frequency] ?? g.frequency}',
            key: const Key('group_amount'),
            style: TextStyle(color: soft, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text('${t('Premier tour')} · ${formatDate(g.startDate)}', style: TextStyle(color: soft)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(groupStatusLabels[g.status] ?? g.status, color: color, background: bg),
              StatusPill(
                t('{n} membre(s)', {'n': g.members.length}),
                color: Brand.ink,
                background: Colors.white,
                icon: Icons.people_outline,
              ),
              if (g.isPresident)
                StatusPill(t('Président(e)'), color: Brand.goldDark, background: Brand.goldLight, icon: Icons.star_rounded),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Le tour ouvert, mis en avant : qui reçoit, pour quand, où en sont les confirmations.
class _CurrentCycleCard extends StatelessWidget {
  const _CurrentCycleCard({required this.title, required this.cycle, required this.mine, required this.onOpen});

  final String title;
  final CycleSummary cycle;
  final bool mine;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = cycle.expectedCount == 0 ? 0.0 : cycle.confirmedCount / cycle.expectedCount;
    final accent = mine ? Brand.goldDark : Brand.green;
    return Container(
      key: const Key('current_cycle'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mine ? Brand.goldLight : Brand.mint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(
            cycleStatusLabels['open']!,
            color: Colors.white,
            background: accent,
            icon: mine ? Icons.star_rounded : Icons.autorenew,
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${t('Échéance')} · ${formatDate(cycle.dueDate)}', style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: progress, minHeight: 8, color: accent, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 6),
          Text('${cycle.confirmedCount}/${cycle.expectedCount}', style: TextStyle(color: Brand.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('open_current_cycle'),
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward),
            label: Text(t('Voir le tour')),
          ),
        ],
      ),
    );
  }
}

/// Une ligne du tableau des tours : terminé (coche), en cours (mis en avant), à venir (numéro).
class _CycleTile extends StatelessWidget {
  const _CycleTile({required this.title, required this.cycle, required this.mine, required this.onTap});

  final String title;
  final CycleSummary cycle;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = cycle;
    final (Color fg, Color bg) = switch (c.status) {
      'completed' => (Colors.white, Brand.success),
      'open' => (Colors.white, Brand.green),
      'cancelled' => (Brand.muted, Brand.neutral),
      _ => (Brand.green, Brand.mint),
    };
    return Card(
      color: c.status == 'open' ? Brand.mint : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: CircleAvatar(
          backgroundColor: bg,
          foregroundColor: fg,
          child: c.status == 'completed'
              ? const Icon(Icons.check)
              : Text('${c.cycleNumber}', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        title: Row(
          children: [
            Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (mine) ...[const SizedBox(width: 6), const Icon(Icons.star_rounded, size: 18, color: Brand.goldDark)],
          ],
        ),
        subtitle: Text(
          t('{date} · {status} · {done}/{total} confirmé(s)', {
            'date': formatDate(c.dueDate),
            'status': cycleStatusLabels[c.status],
            'done': c.confirmedCount,
            'total': c.expectedCount,
          }),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Ce qui reste à faire avant de pouvoir démarrer, coché au fur et à mesure.
class _StartChecklist extends StatelessWidget {
  const _StartChecklist({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final terms = g.terms;
    final items = [
      (g.members.length >= 2, t('Au moins 2 membres')),
      (g.hasCompleteOrder, t('Ordre des tours fixé')),
      (terms?.allSigned ?? false, t('Règlement signé par tous')),
    ];
    return Card(
      key: const Key('start_checklist'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(t('Avant de démarrer'), style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final (done, label) in items)
              ListTile(
                dense: true,
                leading: Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: done ? Brand.success : Brand.muted,
                ),
                title: Text(
                  label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: done ? Brand.ink : Brand.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Comment l'ordre a été fixé : la transparence passe aussi par là.
class _OrderInfo extends StatelessWidget {
  const _OrderInfo({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final seed = group.drawSeed;
    final text = switch (group.turnOrderMode) {
      'draw' => t('Ordre tiré au sort. Graine publique : {seed}…', {'seed': seed!.substring(0, 16)}),
      'chosen' when seed != null => t('Ordre choisi par le président (un tirage au sort avait eu lieu avant).'),
      'chosen' => t('Ordre choisi par le président.'),
      _ => t('Ordre des tours pas encore fixé.'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Brand.muted)),
    );
  }
}
