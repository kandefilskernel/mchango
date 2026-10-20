import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';

/// « J'ai payé » : moyen de paiement, puis ID de transaction (mobile money) ou témoin (espèces).
class DeclareScreen extends StatefulWidget {
  const DeclareScreen({
    super.key,
    required this.group,
    required this.cycleNumber,
    required this.beneficiary,
  });

  final Group group;
  final int cycleNumber;
  final Member beneficiary;

  @override
  State<DeclareScreen> createState() => _DeclareScreenState();
}

class _DeclareScreenState extends State<DeclareScreen> {
  /// Créé une fois : renvoyer la déclaration après une coupure réseau ne crée pas de doublon.
  final String _offlineId = uuidV4();
  final _txReference = TextEditingController();
  String? _method;
  String? _witnessId;

  static const _methods = [
    ('mpesa', Icons.phone_android),
    ('airtel', Icons.phone_android),
    ('orange', Icons.phone_android),
    ('cash', Icons.payments),
  ];

  @override
  void dispose() {
    _txReference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final services = Services.of(context);
    final isCash = _method == 'cash';
    if (!isCash && _txReference.text.trim().length < 5) {
      return showInfo(context, "Entrez l'ID de transaction reçu par SMS.");
    }
    if (isCash && _witnessId == null) return showInfo(context, 'Choisissez un témoin.');
    await services.api.declare(
      groupId: widget.group.id,
      cycleNumber: widget.cycleNumber,
      method: _method!,
      amountMinor: widget.group.contributionAmountMinor,
      offlineId: _offlineId,
      txReference: isCash ? null : _txReference.text.trim(),
      witnessMembershipId: isCash ? _witnessId : null,
    );
    if (!mounted) return;
    showInfo(context, 'Paiement déclaré. ${widget.beneficiary.fullName} doit maintenant confirmer.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final myUserId = Services.of(context).auth.userId;
    final witnesses = g.members
        .where((m) => m.userId != myUserId && m.membershipId != widget.beneficiary.membershipId)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text("J'ai payé")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatAmount(g.contributionAmountMinor, g.currency),
                  style: Theme.of(context).textTheme.headlineMedium),
              Text('à ${widget.beneficiary.fullName} · ${widget.beneficiary.phone}'),
              Text('Tour ${widget.cycleNumber}'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('Comment avez-vous payé ?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.4,
          children: [
            for (final (method, icon) in _methods)
              ChoiceChip(
                key: Key('method_$method'),
                avatar: Icon(icon),
                label: SizedBox(width: double.infinity, child: Text(methodLabels[method]!)),
                selected: _method == method,
                onSelected: (_) => setState(() => _method = method),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_method != null && _method != 'cash') ...[
          TextField(
            key: const Key('tx_reference'),
            controller: _txReference,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'ID de transaction',
              helperText: 'Dans le SMS de confirmation de votre opérateur',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_method == 'cash') ...[
          const Text(
              'Un autre membre doit avoir vu la remise. Il confirmera, en plus du bénéficiaire.'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('witness'),
            initialValue: _witnessId,
            decoration: const InputDecoration(labelText: 'Témoin', border: OutlineInputBorder()),
            items: [
              for (final m in witnesses) DropdownMenuItem(value: m.membershipId, child: Text(m.fullName)),
            ],
            onChanged: (v) => setState(() => _witnessId = v),
          ),
          if (witnesses.isEmpty)
            const Text("Aucun autre membre ne peut être témoin dans ce groupe : payez par mobile money."),
        ],
        const SizedBox(height: 24),
        BusyButton(label: 'Déclarer le paiement', onPressed: _method == null ? null : _submit),
        const SizedBox(height: 12),
        Text(noCustodyNotice, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}
