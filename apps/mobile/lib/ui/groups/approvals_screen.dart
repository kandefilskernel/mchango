import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// Le garant confirme (ou refuse) qu'un membre demande bien un nouveau PIN.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  int _version = 0;

  /// Demande en cours d'envoi (boutons désactivés pendant ce temps).
  String? _sending;

  Future<void> _decide(PinResetRequest r, bool approve) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? t('Confirmer pour {name} ?', {'name': r.fullName}) : t('Refuser la demande ?')),
        content: Text(
          approve
              ? t(
                  "Confirmez seulement si vous avez parlé à {name} de vive voix (en personne ou en reconnaissant sa voix au téléphone) et qu'elle vous a dit avoir oublié son PIN.\n\nSi quelqu'un d'autre a pris son numéro, confirmer lui donnerait accès à son compte.",
                  {'name': r.fullName},
                )
              : t(
                  "{name} ne pourra pas changer de PIN avec cette demande. Refusez si vous ne l'avez pas reconnue ou si elle ne vous a rien demandé.",
                  {'name': r.fullName},
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
          FilledButton(
            style: approve ? null : FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? t('Je confirme') : t('Refuser')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = Services.of(context).api;
    setState(() => _sending = r.requestId);
    try {
      await (approve ? api.approvePinReset(r.requestId) : api.rejectPinReset(r.requestId));
      if (!mounted) return;
      showInfo(context, approve ? t('{name} peut maintenant utiliser son nouveau PIN.', {'name': r.fullName}) : t('Demande refusée.'));
      setState(() => _version++);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Demandes à confirmer'))),
      body: Loader<List<PinResetRequest>>(
        key: ValueKey(_version),
        load: Services.of(context).api.pendingPinResets,
        builder: (context, requests, reload) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (requests.isEmpty) Padding(padding: EdgeInsets.all(24), child: Text(t('Aucune demande en attente.'))),
            for (final r in requests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFFFF3D6),
                            child: Icon(Icons.key, color: Brand.goldDark),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                Text(t('{phone} · tontine {group}', {'phone': r.phone, 'group': r.groupName})),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(t('Demande un nouveau PIN · {date}', {'date': formatDateTime(r.createdAt)})),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _sending == null ? () => _decide(r, false) : null,
                              child: Text(t('Refuser')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _sending == null ? () => _decide(r, true) : null,
                              child: _sending == r.requestId
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                    )
                                  : Text(t('Confirmer')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
