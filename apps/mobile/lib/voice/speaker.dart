import 'package:flutter_tts/flutter_tts.dart';

import '../l10n/l10n.dart';

/// Lecture à voix haute, pour les membres qui lisent peu ou pas : l'écran dit l'essentiel.
abstract class Speaker {
  /// Lit [text] dans la langue de l'app. Une nouvelle lecture coupe la précédente.
  Future<void> say(String text);

  Future<void> stop();
}

/// Voix du téléphone (synthèse vocale d'Android, ou du navigateur en web).
///
/// Français, swahili et anglais ont en général une voix sur les téléphones. Le lingala n'en a
/// presque jamais : la voix française le lit alors, ce qui reste compréhensible (le lingala s'écrit
/// comme il se prononce), mais des enregistrements par des locutrices feraient mieux.
class DeviceSpeaker implements Speaker {
  late final _tts = FlutterTts();

  static const _voices = {
    AppLanguage.fr: ['fr-FR', 'fr'],
    AppLanguage.sw: ['sw-KE', 'sw-TZ', 'sw'],
    AppLanguage.ln: ['ln-CD', 'ln', 'fr-FR'],
    AppLanguage.en: ['en-GB', 'en-US', 'en'],
  };

  @override
  Future<void> say(String text) async {
    try {
      await _tts.stop();
      for (final code in _voices[Lang.instance.current]!) {
        final ok = await _tts.isLanguageAvailable(code);
        if (ok == true || ok == 1) {
          await _tts.setLanguage(code);
          break;
        }
      }
      await _tts.setSpeechRate(0.42); // lentement : on écoute, on ne lit pas
      await _tts.speak(text);
    } catch (_) {
      // Pas de voix sur ce téléphone : l'écran reste lisible, rien ne casse
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
