import 'package:flutter/material.dart';

import '../../services.dart';
import '../common.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// Ouverture de l'app : PIN vérifié sur le téléphone, puis session signée par la clé de l'appareil.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pin = TextEditingController();
  bool _biometric = false;

  @override
  void initState() {
    super.initState();
    // Empreinte activée : la fenêtre s'ouvre d'elle-même, le PIN reste possible dessous
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Services.of(context).auth;
      final enabled = await auth.biometricEnabled() && await auth.biometricAvailable();
      if (!mounted || !enabled) return;
      setState(() => _biometric = true);
      await _unlockWithBiometric();
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlockWithBiometric() async {
    try {
      final ok = await Services.of(context).auth.unlockWithBiometric();
      if (!ok && mounted) showInfo(context, t('Empreinte non reconnue. Utilisez votre PIN.'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _unlock() async {
    final auth = Services.of(context).auth;
    final wait = await auth.lockRemaining();
    if (!mounted) return;
    if (wait != null) {
      return showInfo(context, t('Trop d\'essais. Réessayez dans {n} minute(s).', {'n': wait.inMinutes + 1}));
    }
    if (!await auth.unlock(_pin.text)) {
      _pin.clear();
      if (mounted) showInfo(context, t('PIN incorrect.'));
    }
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Oublier ce téléphone ?')),
        content: Text(
          t('Pour revenir, il faudra un code SMS et votre PIN. Vos groupes et cotisations ne sont pas effacés.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Oublier'))),
        ],
      ),
    );
    if (ok == true && mounted) await Services.of(context).auth.forgetDevice();
  }

  @override
  Widget build(BuildContext context) {
    final name = Services.of(context).auth.fullName;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Center(child: BrandMark(size: 40)),
            const SizedBox(height: 24),
            const Illustration('verifie', height: 150),
            const SizedBox(height: 16),
            Text(
              name == null ? 'Mchango' : t('Bonjour {name}', {'name': name}),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PinField(key: const Key('unlock_pin'), controller: _pin, label: t('Votre PIN'), autofocus: true),
            const SizedBox(height: 16),
            BusyButton(label: t('Ouvrir'), onPressed: _unlock),
            if (_biometric) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('unlock_biometric'),
                onPressed: _unlockWithBiometric,
                icon: const Icon(Icons.fingerprint, size: 28),
                label: Text(t('Utiliser mon empreinte')),
              ),
            ],
            const SizedBox(height: 24),
            TextButton(onPressed: _forget, child: Text(t('Ce n\'est pas mon compte / PIN oublié'))),
          ],
        ),
      ),
    );
  }
}
