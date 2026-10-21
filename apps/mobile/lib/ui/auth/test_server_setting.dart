import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services.dart';
import '../common.dart';

/// Versions de test seulement : choisir l'adresse de l'API (ex. le PC de développement sur le Wi-Fi).
class TestServerSetting extends StatefulWidget {
  const TestServerSetting({super.key});

  @override
  State<TestServerSetting> createState() => _TestServerSettingState();
}

class _TestServerSettingState extends State<TestServerSetting> {
  Future<void> _edit() async {
    final services = Services.of(context);
    final controller = TextEditingController(text: services.client.baseUrl.replaceFirst('http://', ''));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Serveur de test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Adresse de l'API sur le PC de développement (même Wi-Fi que ce téléphone)."),
            const SizedBox(height: 12),
            TextField(
              key: const Key('test_server_field'),
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: '10.163.102.131:3000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final url = normalizeServerUrl(value);
    if (url == null) return showInfo(context, 'Adresse invalide. Exemple : 10.163.102.131:3000');
    await services.store.write(testServerKey, url);
    setState(() => services.client.baseUrl = url);
    if (mounted) showInfo(context, 'Serveur de test : $url');
  }

  @override
  Widget build(BuildContext context) {
    if (!testServerSettingEnabled) return const SizedBox.shrink();
    return TextButton.icon(
      key: const Key('test_server'),
      onPressed: _edit,
      icon: const Icon(Icons.dns_outlined, size: 18),
      label: Text('Serveur de test : ${Services.of(context).client.baseUrl}'),
    );
  }
}
