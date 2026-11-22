import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../l10n/server_messages.dart';
import '../services.dart';
import 'theme.dart';

/// Erreur à montrer : le message du serveur traduit et simplifié (l10n/server_messages.dart).
String errorMessage(Object error) =>
    error is ApiException ? serverMessage(error.message) : serverMessage('Une erreur est survenue. Réessayez.');

/// Erreur bien visible : icône, fond rouge, et le temps de la lire (8 secondes).
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Brand.danger,
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(errorMessage(error), style: const TextStyle(fontSize: 16, color: Colors.white))),
          ],
        ),
      ),
    );
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(t(message), style: const TextStyle(fontSize: 16)),
      ),
    );
}

/// Gros bouton qui affiche un indicateur pendant l'action et montre l'erreur éventuelle.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.icon, this.outlined = false});

  final String label;
  final IconData? icon;

  /// null : bouton désactivé.
  final Future<void> Function()? onPressed;
  final bool outlined;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final child = _busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Text(widget.label);
    final style = ButtonStyle(minimumSize: WidgetStateProperty.all(const Size.fromHeight(52)));
    final icon = widget.icon == null || _busy ? null : Icon(widget.icon);
    if (widget.outlined) {
      return icon == null
          ? OutlinedButton(style: style, onPressed: onPressed, child: child)
          : OutlinedButton.icon(style: style, onPressed: onPressed, icon: icon, label: child);
    }
    return icon == null
        ? FilledButton(style: style, onPressed: onPressed, child: child)
        : FilledButton.icon(style: style, onPressed: onPressed, icon: icon, label: child);
  }
}

/// Charge des données, affiche l'attente, l'erreur (avec « Réessayer ») ou le contenu.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();

  Future<void> _reload() async {
    final next = widget.load();
    // Bloc et non flèche : setState ne doit pas recevoir une fonction qui renvoie un Future
    setState(() {
      _future = next;
    });
    await next.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(color: Brand.goldLight, shape: BoxShape.circle),
                    child: const Icon(Icons.cloud_off_rounded, size: 40, color: Brand.goldDark),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('Impossible de charger'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    errorMessage(snapshot.error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.muted),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('Réessayer')),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Brand.green)),
          );
        }
        return widget.builder(context, snapshot.data as T, _reload);
      },
    );
  }
}

/// Champ PIN : 6 chiffres masqués, clavier numérique.
class PinField extends StatelessWidget {
  const PinField({super.key, required this.controller, required this.label, this.autofocus = false});

  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    keyboardType: TextInputType.number,
    maxLength: 6,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 24, letterSpacing: 12),
    decoration: InputDecoration(labelText: label, counterText: ''),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// Rappel affiché là où l'on parle d'argent.
String get noCustodyNotice => t('Mchango ne détient, ne transfère et ne garantit aucun fonds.');

/// Bouton « Écouter » : l'écran dit l'essentiel à voix haute, pour qui lit peu ou pas.
/// [text] est calculé au moment du toucher, dans la langue de l'app.
class ListenButton extends StatelessWidget {
  const ListenButton({super.key, required this.text, this.light = false});

  final String Function() text;

  /// Sur un fond vert (barre du haut) : icône blanche.
  final bool light;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('listen'),
    tooltip: t('Écouter'),
    iconSize: 28,
    color: light ? Colors.white : Brand.green,
    icon: const Icon(Icons.volume_up_rounded),
    onPressed: () => Services.of(context).speaker.say(text()),
  );
}

/// Texte pour la voix : « 20 000 FC » se dit « 20 000 francs », « 20,50 $ » « 20,50 dollars ».
String spoken(Iterable<String> parts) => parts
    .where((p) => p.trim().isNotEmpty)
    .join('. ')
    .replaceAll(' FC', ' ${t('francs')}')
    .replaceAll(r' $', ' ${t('dollars')}');
