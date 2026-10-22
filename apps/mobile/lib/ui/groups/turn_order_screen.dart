import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../common.dart';
import '../../l10n/l10n.dart';

/// Le président fixe l'ordre des tours : en glissant les membres, ou par tirage au sort vérifiable.
class TurnOrderScreen extends StatefulWidget {
  const TurnOrderScreen({super.key, required this.group});

  final Group group;

  @override
  State<TurnOrderScreen> createState() => _TurnOrderScreenState();
}

class _TurnOrderScreenState extends State<TurnOrderScreen> {
  late final List<Member> _members = [...widget.group.members]
    ..sort((a, b) => (a.turnOrder ?? 999).compareTo(b.turnOrder ?? 999));

  Future<void> _save() async {
    await Services.of(context).api.setChosenOrder(widget.group.id, [for (final m in _members) m.membershipId]);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _draw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Tirer au sort ?')),
        content: Text(
          t(
            "Le tirage ne peut être fait qu'une fois pour ces membres. Son résultat et sa graine seront visibles par tous dans l'historique, et chacun pourra le vérifier.",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Tirer au sort'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await Services.of(context).api.draw(widget.group.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Résultat du tirage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final o in result.order) Text(t('Tour {n} : {name}', {'n': o.turn, 'name': o.fullName})),
            const SizedBox(height: 12),
            SelectableText(t('Graine : {seed}', {'seed': result.seed}), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('OK')))],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Ordre des tours'))),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(t('Glissez les membres pour choisir qui reçoit en premier, ou tirez au sort.')),
          ),
          Expanded(
            child: ReorderableListView(
              onReorderItem: (from, to) => setState(() => _members.insert(to, _members.removeAt(from))),
              children: [
                for (final (i, m) in _members.indexed)
                  ListTile(
                    key: ValueKey(m.membershipId),
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(m.fullName),
                    subtitle: Text(t('Reçoit au tour {n}', {'n': i + 1})),
                    trailing: const Icon(Icons.drag_handle),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                BusyButton(label: t('Enregistrer cet ordre'), onPressed: _save),
                const SizedBox(height: 12),
                BusyButton(label: t('Tirer au sort'), icon: Icons.casino_outlined, outlined: true, onPressed: _draw),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
