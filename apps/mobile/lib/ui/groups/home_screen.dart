import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'create_group_screen.dart';
import 'group_screen.dart';
import 'join_group_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Incrémenté au retour d'un écran : recharge la liste.
  int _version = 0;

  void _refresh() => setState(() => _version++);

  Future<void> _open(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final firstName = (services.auth.fullName ?? '').split(' ').first;
    return Scaffold(
      body: Loader<List<Group>>(
        key: ValueKey(_version),
        load: services.api.myGroups,
        builder: (context, groups, reload) => RefreshIndicator(
          onRefresh: reload,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(
                  greeting: firstName.isEmpty ? 'Bonjour' : 'Bonjour $firstName',
                  groups: groups,
                  onMenu: (v) => v == 'lock' ? services.auth.lock() : services.auth.forgetDevice(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.group_add,
                            label: 'Rejoindre',
                            caption: 'avec un code',
                            onTap: () => _open(context, const JoinGroupScreen()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionTile(
                            icon: Icons.add_circle_outline,
                            label: 'Créer',
                            caption: 'une tontine',
                            onTap: () => _open(context, const CreateGroupScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Mes tontines', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (groups.isEmpty) const _EmptyState(),
                    for (final g in groups)
                      _GroupCard(
                        group: g,
                        onTap: () => _open(context, GroupScreen(groupId: g.id)),
                      ),
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

class _Header extends StatelessWidget {
  const _Header({required this.greeting, required this.groups, required this.onMenu});

  final String greeting;
  final List<Group> groups;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final active = groups.where((g) => g.status == 'active').length;
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandMark(size: 30, light: true),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: onMenu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'lock', child: Text('Verrouiller')),
                      PopupMenuItem(value: 'forget', child: Text('Se déconnecter de ce téléphone')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                greeting,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                groups.isEmpty
                    ? 'Rejoignez ou créez votre première tontine.'
                    : '${groups.length} tontine(s) · $active en cours',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.caption, required this.onTap});

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Brand.ink.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.mint, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Brand.green),
            ),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(caption, style: TextStyle(color: Brand.ink.withValues(alpha: 0.6))),
          ],
        ),
      ),
    ),
  );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final (color, bg) = switch (g.status) {
      'active' => (Brand.green, Brand.mint),
      'closed' => (Brand.ink.withValues(alpha: 0.6), const Color(0xFFEDEFF1)),
      _ => (Brand.goldDark, const Color(0xFFFFF3D6)),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Brand.green, borderRadius: BorderRadius.circular(14)),
                child: Text(
                  g.name.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatAmount(g.contributionAmountMinor, g.currency)} · ${frequencyLabels[g.frequency]}',
                      style: TextStyle(color: Brand.ink.withValues(alpha: 0.7)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(groupStatusLabels[g.status] ?? g.status, color, bg),
                        _Pill('${g.memberCount} membre(s)', Brand.ink.withValues(alpha: 0.7), const Color(0xFFF0F2F1)),
                        if (g.isPresident) const _Pill('Président(e)', Brand.goldDark, Color(0xFFFFF3D6)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color, this.background);

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        const Illustration('seul', height: 160),
        const SizedBox(height: 12),
        Text(
          "Vous n'êtes encore dans aucune tontine.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Seul, épargner prend du temps. Ensemble, chacun reçoit à son tour.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.ink.withValues(alpha: 0.65)),
        ),
      ],
    ),
  );
}
