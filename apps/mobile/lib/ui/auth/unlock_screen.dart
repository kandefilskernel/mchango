import 'package:flutter/material.dart';

import '../../services.dart';
import '../common.dart';
import '../theme.dart';

/// Ouverture de l'app : PIN vérifié sur le téléphone, puis session signée par la clé de l'appareil.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final auth = Services.of(context).auth;
    final wait = await auth.lockRemaining();
    if (!mounted) return;
    if (wait != null) {
      return showInfo(context, 'Trop d\'essais. Réessayez dans ${wait.inMinutes + 1} minute(s).');
    }
    if (!await auth.unlock(_pin.text)) {
      _pin.clear();
      if (mounted) showInfo(context, 'PIN incorrect.');
    }
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Oublier ce téléphone ?'),
        content: const Text(
          'Pour revenir, il faudra un code SMS et votre PIN. Vos groupes et cotisations ne sont pas effacés.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oublier')),
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
              name == null ? 'Mchango' : 'Bonjour $name',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            PinField(key: const Key('unlock_pin'), controller: _pin, label: 'Votre PIN', autofocus: true),
            const SizedBox(height: 16),
            BusyButton(label: 'Ouvrir', onPressed: _unlock),
            const SizedBox(height: 24),
            TextButton(onPressed: _forget, child: const Text('Ce n\'est pas mon compte / PIN oublié')),
          ],
        ),
      ),
    );
  }
}
