import 'package:flutter/material.dart';

import '../../auth/auth_repository.dart';
import '../../services.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// « PIN oublié » en attente : qui doit confirmer, et vérifier si c'est fait.
class PendingResetScreen extends StatefulWidget {
  const PendingResetScreen({super.key});

  @override
  State<PendingResetScreen> createState() => _PendingResetScreenState();
}

class _PendingResetScreenState extends State<PendingResetScreen> {
  PinResetState? _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(quiet: true));
  }

  Future<void> _check({bool quiet = false}) async {
    try {
      final state = await Services.of(context).auth.checkPinReset();
      if (!mounted) return;
      setState(() => _state = state);
      final message = switch (state.status) {
        'pending' when !quiet => t('Pas encore confirmé. Réessayez après avoir parlé à votre garant.'),
        'rejected' => t('Votre garant a refusé la demande. Recommencez si besoin.'),
        'expired' => t('La demande a expiré (48 heures). Recommencez.'),
        'cancelled' => t('Demande annulée.'),
        _ => null,
      };
      if (message != null) showInfo(context, message);
    } catch (e) {
      if (mounted && !quiet) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guarantors = _state?.guarantors ?? const <Guarantor>[];
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const BrandMark(size: 30)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Illustration('ensemble', height: 160),
          const SizedBox(height: 20),
          Text(t('Votre garant doit confirmer'), style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            t("Pour protéger votre argent, un code SMS ne suffit pas pour changer de PIN : quelqu'un pourrait avoir pris votre numéro. Une personne de votre tontine doit confirmer que c'est bien vous."),
            style: text.bodyLarge?.copyWith(color: Brand.ink.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 16),
          if (guarantors.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t("Appelez ou allez voir l'une de ces personnes :"), style: text.titleSmall),
                    const SizedBox(height: 8),
                    for (final g in guarantors)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Brand.mint,
                          child: Icon(Icons.person, color: Brand.green),
                        ),
                        title: Text(g.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(t('Tontine {name}', {'name': g.groupName})),
                      ),
                    const SizedBox(height: 4),
                    Text(t('Elle a reçu un SMS et confirmera dans son application.')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          BusyButton(
            key: const Key('check_reset'),
            label: t("J'ai parlé à mon garant : vérifier"),
            icon: Icons.refresh,
            onPressed: _check,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Services.of(context).auth.cancelPinReset(),
            child: Text(t('Annuler la demande')),
          ),
        ],
      ),
    );
  }
}
