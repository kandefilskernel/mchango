import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services.dart';
import '../language_picker.dart';
import '../theme.dart';

class _Slide {
  const _Slide(this.image, this.title, this.text);
  final String image;
  final String title;
  final String text;
}

/// L'histoire de la tontine, en quatre images. Le message reste honnête : la tontine ne crée
/// pas d'argent, elle permet de disposer tôt d'une grosse somme pour réaliser un projet.
// Getter : les textes suivent la langue choisie
List<_Slide> get _slides => [
  _Slide(
    'seul',
    t('Seul, c\'est long'),
    t('Mettre de côté petit à petit, tout seul, peut prendre des années avant de pouvoir lancer son projet.'),
  ),
  _Slide(
    'ensemble',
    t('Ensemble, on cotise'),
    t('À chaque tour, chaque membre verse le même petit montant, directement au membre dont c\'est le tour.'),
  ),
  _Slide(
    'projet',
    t('À chaque tour, un membre reçoit tout'),
    t('La somme de tous les membres : de quoi acheter une moto, ouvrir une boutique, payer les études.'),
  ),
  _Slide(
    'verifie',
    t('Tout est vérifiable'),
    t('Chaque paiement est déclaré, confirmé par celui qui reçoit, et inscrit dans un journal que personne ne peut modifier.'),
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone, this.askLanguage = false, this.onLanguageChosen});

  final VoidCallback onDone;

  /// Montrer d'abord le choix de la langue (premier lancement, aucune langue enregistrée).
  final bool askLanguage;
  final VoidCallback? onLanguageChosen;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;


  bool get _last => _index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() => _last
      ? widget.onDone()
      : _pages.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    if (widget.askLanguage) {
      return _LanguageFirst(
        onChosen: (l) async {
          // Changer de langue redessine toute l'app : le choix est retenu par l'app elle-même
          widget.onLanguageChosen?.call();
          await Lang.instance.set(l, Services.of(context).store);
        },
      );
    }
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.cream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  const BrandMark(size: 30),
                  const Spacer(),
                  if (!_last) TextButton(onPressed: widget.onDone, child: Text(t('Passer'))),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 8), child: LanguagePicker()),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: Illustration(s.image, semanticLabel: s.title)),
                        const SizedBox(height: 24),
                        Text(s.title, textAlign: TextAlign.center, style: text.headlineSmall),
                        const SizedBox(height: 12),
                        Text(
                          s.text,
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(color: Brand.ink.withValues(alpha: 0.75), height: 1.4),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? Brand.green : Brand.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: FilledButton(
                key: const Key('onboarding_next'),
                onPressed: _next,
                child: Text(_last ? t('Commencer') : t('Suivant')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tout premier écran : la langue, en gros boutons, chaque langue écrite dans sa langue avec un mot
/// de salut qu'on reconnaît sans lire. Swahili et lingala d'abord : ce sont les langues des mamans
/// (Lubumbashi, Kinshasa) ; le français et l'anglais suivent.
class _LanguageFirst extends StatelessWidget {
  const _LanguageFirst({required this.onChosen});

  final ValueChanged<AppLanguage> onChosen;

  static const _choices = [
    (AppLanguage.sw, 'Habari'),
    (AppLanguage.ln, 'Mbote'),
    (AppLanguage.fr, 'Bonjour'),
    (AppLanguage.en, 'Hello'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Brand.cream,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          const Center(child: BrandMark(size: 36)),
          const SizedBox(height: 20),
          SizedBox(height: 150, child: Illustration('ensemble', semanticLabel: 'Mchango')),
          const SizedBox(height: 20),
          // La question dans les quatre langues : chacune la trouve dans la sienne
          for (final line in const ['Chagua lugha yako', 'Pona lokota na yo', 'Choisissez votre langue', 'Choose your language'])
            Text(
              line,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.ink, height: 1.5),
            ),
          const SizedBox(height: 24),
          for (final (language, hello) in _choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: Brand.green.withValues(alpha: 0.25), width: 1.5),
                ),
                child: InkWell(
                  key: Key('first_lang_${language.code}'),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onChosen(language),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: Brand.mint, shape: BoxShape.circle),
                          child: Text(
                            language.code.toUpperCase(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Brand.green),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(language.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              Text(hello, style: TextStyle(fontSize: 16, color: Brand.muted)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded, color: Brand.green, size: 28),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Écran de démarrage : logo et image de la tontine, pendant le chargement.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: Brand.headerGradient),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const BrandMark(size: 56, light: true),
            const SizedBox(height: 12),
            Text(
              t('Chaque cotisation, vérifiable.'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Illustration('ensemble', semanticLabel: t('Des membres cotisent ensemble')),
              ),
            ),
            const Spacer(),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
            ),
            const SizedBox(height: 28),
            const PublisherSignature(light: true),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}
