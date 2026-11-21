import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';

/// Attestation de régularité (spec/attestations.md) : un relevé figé de mes cotisations, à montrer
/// à une IMF, une coopec ou un bailleur. Il se vérifie par son code ou son QR. Ce n'est ni une note
/// ni une garantie : des faits constatés dans le journal.
class AttestationScreen extends StatefulWidget {
  const AttestationScreen({super.key});

  @override
  State<AttestationScreen> createState() => _AttestationScreenState();
}

class _AttestationScreenState extends State<AttestationScreen> {
  int _version = 0;
  bool _includeAmounts = false;

  Future<(AttestationStats, List<Attestation>)> _load() async {
    final api = Services.of(context).api;
    return (await api.attestationStats(), await api.myAttestations());
  }

  Future<void> _issue() async {
    final a = await Services.of(context).api.issueAttestation(includeAmounts: _includeAmounts);
    if (!mounted) return;
    setState(() => _version++);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AttestationCardScreen(attestation: a)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Attestation de régularité'))),
      body: Loader<(AttestationStats, List<Attestation>)>(
        key: ValueKey(_version),
        load: _load,
        builder: (context, data, reload) {
          final (stats, issued) = data;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  t(
                    'Prouvez votre sérieux à une IMF, une coopec ou un bailleur : vos cotisations confirmées, vérifiables par un code.',
                  ),
                  style: TextStyle(color: Brand.muted),
                ),
                const SizedBox(height: 12),
                StatsCard(stats: stats),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('attestation_amounts'),
                  contentPadding: EdgeInsets.zero,
                  value: _includeAmounts,
                  onChanged: (v) => setState(() => _includeAmounts = v),
                  title: Text(t('Inclure les montants versés')),
                  subtitle: Text(t('Sinon, seuls les nombres de paiements apparaissent.')),
                ),
                BusyButton(
                  label: t('Créer une attestation'),
                  icon: Icons.verified_outlined,
                  onPressed: stats.confirmed == 0 ? null : _issue,
                ),
                if (stats.confirmed == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      t('Disponible après votre premier paiement confirmé.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Brand.muted),
                    ),
                  ),
                if (issued.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(t('Mes attestations'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final a in issued)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          a.status == 'valid' ? Icons.verified : Icons.block,
                          color: a.status == 'valid' ? Brand.success : Brand.muted,
                        ),
                        title: Text(
                          a.displayCode,
                          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
                        ),
                        subtitle: Text(
                          '${_statusLabel(a.status)} · ${t('jusqu\'au {date}', {'date': formatDateTime(a.expiresAt)})}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => AttestationCardScreen(attestation: a)),
                          );
                          if (mounted) setState(() => _version++);
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  t('Une attestation reprend les faits enregistrés ; ce n\'est pas un score de crédit. {notice}', {
                    'notice': noCustodyNotice,
                  }),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Brand.muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'valid' => t('Valable'),
  'expired' => t('Expirée'),
  _ => t('Retirée'),
};

/// Les chiffres d'une attestation : paiements à temps, en retard, tours reçus.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.stats});

  final AttestationStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.onTimeRatePercent == null ? '—' : '${s.onTimeRatePercent} %',
              key: const Key('on_time_rate'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Brand.green),
            ),
            Text(t('des paiements confirmés faits à temps'), textAlign: TextAlign.center),
            const Divider(height: 24),
            InfoRow(t('Paiements confirmés'), '${s.confirmed}'),
            InfoRow(t('À temps'), '${s.onTime}'),
            InfoRow(t('En retard'), '${s.late}'),
            if (s.rejected > 0) InfoRow(t('Rejetés'), '${s.rejected}'),
            InfoRow(t('Tours reçus'), '${s.turnsReceived}'),
            InfoRow(
              t('Tontines'),
              t('{n} dont {done} terminée(s)', {'n': s.tontinesJoined, 'done': s.tontinesCompleted}),
            ),
            InfoRow(t('Membre depuis'), formatDate(s.memberSince)),
          ],
        ),
      ),
    );
  }
}

/// Une attestation émise : à montrer, à partager en image, ou à retirer.
class AttestationCardScreen extends StatefulWidget {
  const AttestationCardScreen({super.key, required this.attestation});

  final Attestation attestation;

  @override
  State<AttestationCardScreen> createState() => _AttestationCardScreenState();
}

class _AttestationCardScreenState extends State<AttestationCardScreen> {
  final _cardKey = GlobalKey();

  String get _shareText => t(
    'Attestation de régularité Mchango de {name} : code {code}, valable jusqu\'au {date}. Vérification dans l\'application Mchango.',
    {
      'name': widget.attestation.holderName,
      'code': widget.attestation.displayCode,
      'date': formatDateTime(widget.attestation.expiresAt),
    },
  );

  Future<void> _share() async {
    final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _shareText,
          files: [
            XFile.fromData(
              png!.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'attestation-${widget.attestation.code}.png',
            ),
          ],
        ),
      );
    } catch (_) {
      await SharePlus.instance.share(ShareParams(text: _shareText));
    }
  }

  Future<void> _revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Retirer cette attestation ?')),
        content: Text(t('Le code ne montrera plus que « retirée ». Cela ne peut pas être annulé.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Retirer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Services.of(context).api.revokeAttestation(widget.attestation.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attestation;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('Attestation'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: Material(
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
                      Text(t('Attestation de régularité'), style: text.titleLarge?.copyWith(color: Colors.black87)),
                      Text(a.holderName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '${_statusLabel(a.status)} · ${t('émise le {date}', {'date': formatDateTime(a.issuedAt)})}',
                        style: TextStyle(color: a.status == 'valid' ? Brand.success : Brand.danger),
                      ),
                      const Divider(height: 24),
                      StatsCard(stats: a.stats),
                      const SizedBox(height: 12),
                      Center(
                        child: QrImageView(
                          data: a.qrPayload,
                          size: 170,
                          backgroundColor: Colors.white,
                          semanticsLabel: t('QR code de l\'attestation {code}', {'code': a.displayCode}),
                        ),
                      ),
                      SelectableText(
                        a.displayCode,
                        key: const Key('attestation_code'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w800,
                          color: Brand.green,
                        ),
                      ),
                      Text(
                        t('Valable jusqu\'au {date} · empreinte {hash}…', {
                          'date': formatDateTime(a.expiresAt),
                          'hash': a.contentHash.substring(0, 16),
                        }),
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(
                          'Cotisations déclarées par ce membre et confirmées par leurs bénéficiaires. Ni score de crédit ni garantie. {notice}',
                          {'notice': noCustodyNotice},
                        ),
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (a.status == 'valid') ...[
            BusyButton(label: t('Partager l\'attestation'), icon: Icons.share, onPressed: _share),
            const SizedBox(height: 12),
            BusyButton(
              label: t('Copier le code'),
              icon: Icons.copy,
              outlined: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: a.displayCode));
                if (context.mounted) showInfo(context, t('Code copié.'));
              },
            ),
            const SizedBox(height: 12),
            BusyButton(label: t('Retirer l\'attestation'), icon: Icons.block, outlined: true, onPressed: _revoke),
          ],
        ],
      ),
    );
  }
}
