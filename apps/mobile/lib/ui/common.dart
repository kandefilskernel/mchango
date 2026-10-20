import 'package:flutter/material.dart';

import '../api/api_client.dart';

String errorMessage(Object error) =>
    error is ApiException ? error.message : 'Une erreur est survenue. Réessayez.';

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Gros bouton qui affiche un indicateur pendant l'action et montre l'erreur éventuelle.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  });

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
    setState(() => _future = next);
    await next.catchError((_) => null as T);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 12),
                Text(errorMessage(snapshot.error!), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
              ]),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
        decoration: InputDecoration(labelText: label, counterText: '', border: const OutlineInputBorder()),
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
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// Rappel affiché là où l'on parle d'argent.
const noCustodyNotice = 'Mchango ne détient, ne transfère et ne garantit aucun fonds.';
