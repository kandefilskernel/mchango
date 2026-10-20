import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes tontines'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'lock' ? services.auth.lock() : services.auth.forgetDevice(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'lock', child: Text('Verrouiller')),
              PopupMenuItem(value: 'forget', child: Text('Se déconnecter de ce téléphone')),
            ],
          ),
        ],
      ),
      body: Loader<List<Group>>(
        key: ValueKey(_version),
        load: services.api.myGroups,
        builder: (context, groups, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (groups.isEmpty) ...[
              const SizedBox(height: 32),
              const Icon(Icons.groups_outlined, size: 64),
              const SizedBox(height: 12),
              const Text('Vous n\'êtes encore dans aucune tontine.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
            ],
            for (final g in groups)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(child: Text(g.name.characters.first.toUpperCase())),
                  title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${formatAmount(g.contributionAmountMinor, g.currency)} · '
                      '${frequencyLabels[g.frequency]}\n'
                      '${groupStatusLabels[g.status]} · ${g.memberCount} membre(s)'
                      '${g.isPresident ? ' · Président(e)' : ''}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(context, GroupScreen(groupId: g.id)),
                ),
              ),
            const SizedBox(height: 16),
            BusyButton(
              label: 'Rejoindre avec un code',
              icon: Icons.group_add,
              onPressed: () => _open(context, const JoinGroupScreen()),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Créer une tontine',
              icon: Icons.add,
              outlined: true,
              onPressed: () => _open(context, const CreateGroupScreen()),
            ),
          ]),
        ),
      ),
    );
  }
}
