import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../../sms/operator_sms.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// « J'ai payé » : moyen de paiement, puis ID de transaction (mobile money) ou témoin (espèces).
class DeclareScreen extends StatefulWidget {
  const DeclareScreen({super.key, required this.group, required this.cycleNumber, required this.beneficiary});

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

  /// Ce que le SMS collé a appris : affiché pour que la personne vérifie avant d'envoyer.
  OperatorSms? _sms;

  /// « Coller le SMS de confirmation » : remplit l'ID, propose le moyen, vérifie le montant.
  Future<void> _pasteSms() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final sms = parseOperatorSms(text);
    if (!mounted) return;
    if (sms == null || sms.txId == null) {
      setState(() => _sms = null);
      return showInfo(
        context,
        t("Aucun ID de transaction trouvé. Copiez d'abord le SMS de confirmation de votre opérateur."),
      );
    }
    if (sms.kind == SmsKind.withdrawal || sms.kind == SmsKind.received) {
      setState(() => _sms = null);
      return showInfo(
        context,
        sms.kind == SmsKind.withdrawal
            ? t("Ce SMS est un retrait chez un agent, pas un envoi. Copiez le SMS de l'argent envoyé au bénéficiaire.")
            : t("Ce SMS est de l'argent reçu, pas envoyé. Copiez le SMS de l'argent envoyé au bénéficiaire."),
      );
    }
    setState(() {
      _sms = sms;
      _txReference.text = sms.txId!;
      if (sms.method != null && _method == null) _method = sms.method;
    });
  }

  Future<void> _submit() async {
    final services = Services.of(context);
    final isCash = _method == 'cash';
    if (!isCash && _txReference.text.trim().length < 5) {
      return showInfo(context, t("Entrez l'ID de transaction reçu par SMS."));
    }
    if (isCash && _witnessId == null) return showInfo(context, t('Choisissez un témoin.'));
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
    showInfo(context, t('Paiement déclaré. {name} doit maintenant confirmer.', {'name': widget.beneficiary.fullName}));
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
      appBar: AppBar(title: Text(t("J'ai payé"))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatAmount(g.contributionAmountMinor, g.currency),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(t('à {name} · {phone}', {'name': widget.beneficiary.fullName, 'phone': widget.beneficiary.phone})),
                  Text(t('Tour {n}', {'n': widget.cycleNumber})),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(t('Comment avez-vous payé ?'), style: Theme.of(context).textTheme.titleMedium),
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
            OutlinedButton.icon(
              key: const Key('paste_sms'),
              onPressed: _pasteSms,
              icon: const Icon(Icons.content_paste),
              label: Text(t('Coller le SMS de confirmation')),
            ),
            const SizedBox(height: 4),
            Text(
              t("Appuyez longuement sur le SMS de votre opérateur, copiez-le, puis touchez ce bouton. Le SMS reste sur votre téléphone."),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_sms != null) _SmsCheck(sms: _sms!, expectedMinor: g.contributionAmountMinor, currency: g.currency),
            const SizedBox(height: 12),
            TextField(
              key: const Key('tx_reference'),
              controller: _txReference,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: t('ID de transaction'),
                helperText: t('Dans le SMS de confirmation de votre opérateur'),
              ),
            ),
          ],
          if (_method == 'cash') ...[
            Text(t('Un autre membre doit avoir vu la remise. Il confirmera, en plus du bénéficiaire.')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('witness'),
              initialValue: _witnessId,
              decoration: InputDecoration(labelText: t('Témoin')),
              items: [for (final m in witnesses) DropdownMenuItem(value: m.membershipId, child: Text(m.fullName))],
              onChanged: (v) => setState(() => _witnessId = v),
            ),
            if (witnesses.isEmpty)
              Text(t("Aucun autre membre ne peut être témoin dans ce groupe : payez par mobile money.")),
          ],
          const SizedBox(height: 24),
          BusyButton(label: t('Déclarer le paiement'), onPressed: _method == null ? null : _submit),
          const SizedBox(height: 12),
          Text(noCustodyNotice, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Ce que dit le SMS collé, comparé à la cotisation attendue.
class _SmsCheck extends StatelessWidget {
  const _SmsCheck({required this.sms, required this.expectedMinor, required this.currency});

  final OperatorSms sms;
  final int expectedMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final amountOk = sms.amountMinor == expectedMinor && sms.currency == currency;
    final amountText = sms.amountMinor == null || sms.currency == null
        ? t('montant non trouvé dans le SMS')
        : formatAmount(sms.amountMinor!, sms.currency!);
    return Card(
      key: const Key('sms_check'),
      color: amountOk ? Brand.mint : const Color(0xFFFFF3D6),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('ID trouvé : {id}', {'id': sms.txId}), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(amountOk ? Icons.check_circle : Icons.warning_amber_rounded,
                    size: 18, color: amountOk ? Brand.green : Brand.goldDark),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    amountOk
                        ? t('Montant du SMS : {amount}, comme la cotisation.', {'amount': amountText})
                        : t('Montant du SMS : {amount}. La cotisation est de {expected} : vérifiez.', {
                            'amount': amountText,
                            'expected': formatAmount(expectedMinor, currency),
                          }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
