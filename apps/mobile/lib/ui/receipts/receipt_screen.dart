import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../../l10n/l10n.dart';

/// Reçu d'une cotisation confirmée, partageable en image (WhatsApp…).
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.contributionId});

  final String contributionId;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _receiptKey = GlobalKey();

  static String shareText(Receipt r) => t(
    'Reçu Mchango {number} : {payer} a payé {amount} à {beneficiary} ({group}, tour {n}), confirmé le {date}.',
    {
      'number': r.receiptNumber,
      'payer': r.payerName,
      'amount': formatAmount(r.amountMinor, r.currency),
      'beneficiary': r.beneficiaryName,
      'group': r.groupName,
      'n': r.cycleNumber,
      'date': formatDateTime(r.confirmedAt),
    },
  );

  Future<void> _share(Receipt r) async {
    final boundary = _receiptKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText(r),
          files: [
            XFile.fromData(png!.buffer.asUint8List(), mimeType: 'image/png', name: 'recu-${r.receiptNumber}.png'),
          ],
        ),
      );
    } catch (_) {
      // Partage d'image indisponible (navigateur, vieux téléphone) : le texte seul
      await SharePlus.instance.share(ShareParams(text: shareText(r)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Reçu'))),
      body: Loader<Receipt>(
        load: () => Services.of(context).api.receipt(widget.contributionId),
        builder: (context, r, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RepaintBoundary(
              key: _receiptKey,
              child: ReceiptCard(receipt: r),
            ),
            const SizedBox(height: 16),
            BusyButton(label: t('Partager le reçu'), icon: Icons.share, onPressed: () => _share(r)),
          ],
        ),
      ),
    );
  }
}

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.black87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Reçu Mchango'), style: text.titleLarge?.copyWith(color: Colors.black87)),
                        Text(r.receiptNumber, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                formatAmount(r.amountMinor, r.currency),
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(color: Colors.black87),
              ),
              Text('${r.payerName}  →  ${r.beneficiaryName}', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              InfoRow(t('Tontine'), r.groupName),
              InfoRow(t('Tour'), '${r.cycleNumber}'),
              InfoRow(t('Moyen'), methodLabels[r.method] ?? r.method),
              if (r.txReference != null) InfoRow(t('ID de transaction'), r.txReference!),
              if (r.witnessName != null) InfoRow(t('Témoin'), r.witnessName!),
              InfoRow(t('Déclaré le'), formatDateTime(r.declaredAt)),
              InfoRow(t('Confirmé le'), formatDateTime(r.confirmedAt)),
              if (r.isLate) InfoRow(t('Remarque'), t("Payé après l'échéance")),
              const SizedBox(height: 12),
              Center(
                child: QrImageView(
                  data: r.qrPayload,
                  size: 180,
                  backgroundColor: Colors.white,
                  semanticsLabel: t('QR code du reçu {n}', {'n': r.receiptNumber}),
                ),
              ),
              Text(
                t('Journal : événement n°{n} · {hash}…', {'n': r.auditSeq, 'hash': r.auditHash.substring(0, 16)}),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'Ce reçu atteste que le paiement a été déclaré par le payeur et confirmé par le bénéficiaire. {notice}',
                  {'notice': noCustodyNotice},
                ),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
