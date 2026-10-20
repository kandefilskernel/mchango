import 'package:flutter/material.dart';

void main() {
  runApp(const MchangoApp());
}

class MchangoApp extends StatelessWidget {
  const MchangoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mchango',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F5A)),
      ),
      home: const AccueilPage(),
    );
  }
}

/// Écran provisoire, remplacé par l'inscription OTP + PIN (itération 1, semaine 1).
class AccueilPage extends StatelessWidget {
  const AccueilPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Mchango', style: textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Chaque cotisation, vérifiable.',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Mchango ne détient, ne transfère et ne garantit aucun fonds.",
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
