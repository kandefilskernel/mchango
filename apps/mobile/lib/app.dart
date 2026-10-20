import 'package:flutter/material.dart';

import 'auth/auth_repository.dart';
import 'services.dart';
import 'ui/auth/sign_in_flow.dart';
import 'ui/auth/unlock_screen.dart';
import 'ui/groups/home_screen.dart';

class MchangoApp extends StatefulWidget {
  const MchangoApp({super.key, required this.services});

  final AppServices services;

  @override
  State<MchangoApp> createState() => _MchangoAppState();
}

class _MchangoAppState extends State<MchangoApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  AuthStatus? _lastStatus;
  DateTime? _pausedAt;

  /// Après ce délai en arrière-plan, l'app redemande le PIN.
  static const _relockAfter = Duration(minutes: 2);

  AuthRepository get _auth => widget.services.auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Services(
      services: widget.services,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Mchango',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F5A)),
          visualDensity: VisualDensity.standard,
        ),
        home: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => switch (_auth.status) {
            AuthStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
            AuthStatus.signedOut => const SignInFlow(),
            AuthStatus.locked => const UnlockScreen(),
            AuthStatus.signedIn => const HomeScreen(),
          },
        ),
      ),
    );
  }
}
