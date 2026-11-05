import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../common.dart';
import '../theme.dart';

/// « Donner mon avis » : sur Mchango en général ou sur une de mes tontines.
/// L'équipe lit les avis ; un outil d'analyse aide à repérer les problèmes (sans vos nom ni numéro).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.groups});

  final List<Group> groups;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _body = TextEditingController();
  String? _groupId;
  int? _rating;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _body.text.trim();
    if (text.length < 3) {
      showInfo(context, t('Écrivez votre avis.'));
      return;
    }
    await Services.of(context).api.sendFeedback(body: text, groupId: _groupId, rating: _rating);
    if (!mounted) return;
    showInfo(context, t('Merci ! Votre avis a été envoyé à l\'équipe Mchango.'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Donner mon avis'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t('Qu\'est-ce qui marche bien ? Qu\'est-ce qui pose problème ? L\'équipe lit chaque avis.'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String?>(
            key: const Key('feedback_group'),
            initialValue: _groupId,
            decoration: InputDecoration(labelText: t('À propos de')),
            items: [
              DropdownMenuItem(value: null, child: Text(t('Mchango en général'))),
              for (final g in widget.groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
            ],
            onChanged: (v) => setState(() => _groupId = v),
          ),
          const SizedBox(height: 20),
          Text(t('Votre note (facultatif)'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: Key('feedback_star_$i'),
                  tooltip: '$i / 5',
                  onPressed: () => setState(() => _rating = _rating == i ? null : i),
                  icon: Icon(
                    (_rating ?? 0) >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Brand.goldDark,
                    size: 34,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('feedback_body'),
            controller: _body,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: InputDecoration(
              labelText: t('Votre avis'),
              hintText: t('Exemple : le bénéficiaire ne confirme pas mon paiement.'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('N\'écrivez jamais votre PIN ni un code reçu par SMS. Pour un litige sur un paiement, utilisez « Contester » dans le tour concerné.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          BusyButton(key: const Key('feedback_send'), label: t('Envoyer'), icon: Icons.send, onPressed: _send),
        ],
      ),
    );
  }
}
