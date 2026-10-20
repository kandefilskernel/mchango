import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/auth_repository.dart';
import 'services.dart';
import 'ui/auth/sign_in_flow.dart';
import 'ui/auth/unlock_screen.dart';
import 'ui/groups/home_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/theme.dart';

class MchangoApp extends StatefulWidget {
  const MchangoApp({super.key, required this.services});

  final AppServices services;

  /// Durée minimale de l'écran de démarrage, pour qu'on ait le temps de voir l'image.
  static const splashDuration = Duration(milliseconds: 1500);

  @override
  State<MchangoApp> createState() => _MchangoAppState();
}

class _MchangoAppState extends State<MchangoApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AuthStatus? _lastStatus;
  DateTime? _pausedAt;

  /// Après ce délai en arrière-plan, l'app redemande le PIN.
  static const _relockAfter = Duration(minutes: 2);
  static const _kOnboardingDone = 'onboarding_done';

  bool _splashDone = false;
  bool? _onboardingDone;
  Timer? _splashTimer;

  AuthRepository get _auth => widget.services.auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuthChanged);
    _splashTimer = Timer(MchangoApp.splashDuration, () => setState(() => _splashDone = true));
    widget.services.store.read(_kOnboardingDone).then((v) => setState(() => _onboardingDone = v == '1'));
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await widget.services.store.write(_kOnboardingDone, '1');
    setState(() => _onboardingDone = true);
  }

  /// Verrouillage ou déconnexion : on referme les écrans ouverts par-dessus l'accueil.
  void _onAuthChanged() {
    if (_lastStatus == AuthStatus.signedIn && _auth.status != AuthStatus.signedIn) {
      _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    }
    _lastStatus = _auth.status;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed &&
        _pausedAt != null &&
        DateTime.now().difference(_pausedAt!) > _relockAfter &&
        _auth.status == AuthStatus.signedIn) {
      _auth.lock();
    }
  }

  Widget _home() {
    if (!_splashDone || _onboardingDone == null || _auth.status == AuthStatus.loading) {
      return const SplashScreen();
    }
    return switch (_auth.status) {
      AuthStatus.signedOut when !_onboardingDone! => OnboardingScreen(onDone: _finishOnboarding),
      AuthStatus.signedOut => const SignInFlow(),
      AuthStatus.locked => const UnlockScreen(),
      _ => const HomeScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: widget.services,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Mchango',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: KeyedSubtree(key: ValueKey('${_auth.status}-$_splashDone-$_onboardingDone'), child: _home()),
          ),
        ),
      ),
    );
  }
}
