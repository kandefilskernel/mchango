import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import 'group_screen.dart';

/// Code d'invitation → aperçu du groupe et de ses règles → acceptation → adhésion.
class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _code = TextEditingController();
  GroupPreview? _preview;
  bool _accepted = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final preview = await Services.of(context).api.preview(_code.text.trim());
    setState(() {
      _preview = preview;
      _accepted = false;
    });
  }

  Future<void> _join() async {
    final groupId = await Services.of(context).api.join(_code.text.trim());
    if (!mounted) return;
    await Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(groupId: groupId)));
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Rejoindre une tontine')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('invite_code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 22, letterSpacing: 4),
            decoration: const InputDecoration(labelText: "Code d'invitation", hintText: 'K7MP-Q2XW'),
            onChanged: (_) {
              if (_preview != null) setState(() => _preview = null);
            },
          ),
          const SizedBox(height: 12),
          if (p == null) BusyButton(label: 'Voir la tontine', onPressed: _lookUp),
          if (p != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Règlement', style: Theme.of(context).textTheme.titleSmall),
                    InfoRow('Cotisation par tour', formatAmount(p.contributionAmountMinor, p.currency)),
                    InfoRow('Fréquence', frequencyLabels[p.frequency] ?? p.frequency),
                    InfoRow('Premier tour', formatDate(p.startDate)),
                    InfoRow('Membres', '${p.memberCount} / ${p.maxMembers}'),
                    if (p.presidentName != null) InfoRow('Président(e)', p.presidentName!),
                    const SizedBox(height: 8),
                    const Text(
                      'À chaque tour, chaque membre paie directement le bénéficiaire, puis déclare '
                      'son paiement dans Mchango. Le bénéficiaire confirme. Un paiement en espèces '
                      'est aussi confirmé par un témoin. $noCustodyNotice',
                    ),
                  ],
                ),
              ),
            ),
            CheckboxListTile(
              key: const Key('accept_rules'),
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              title: const Text("J'accepte ce règlement"),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            BusyButton(label: 'Rejoindre', onPressed: _accepted ? _join : null),
          ],
        ],
      ),
    );
  }
}
