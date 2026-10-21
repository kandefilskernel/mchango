import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/auth_repository.dart';
import '../../auth/local_pin.dart';
import '../../services.dart';
import '../common.dart';
import '../theme.dart';

enum _Step { phone, code, register, link, forgot }

/// Inscription ou connexion d'un nouveau téléphone, en un seul écran à étapes :
/// numéro → code SMS → (nom + PIN) ou (PIN du compte existant).
class SignInFlow extends StatefulWidget {
  const SignInFlow({super.key});

  @override
  State<SignInFlow> createState() => _SignInFlowState();
}

class _SignInFlowState extends State<SignInFlow> {
  _Step _step = _Step.phone;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _otpToken;

  AuthRepository get _auth => Services.of(context).auth;

  @override
  void dispose() {
    for (final c in [_phone, _code, _name, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode() async {
    await _auth.requestOtp(_phone.text.trim());
    _code.clear();
    setState(() => _step = _Step.code);
  }

  Future<void> _verifyCode() async {
    final result = await _auth.verifyOtp(_phone.text.trim(), _code.text.trim());
    _otpToken = result.otpToken;
    _pin.clear();
    _pin2.clear();
    setState(() => _step = result.accountExists ? _Step.link : _Step.register);
  }

  Future<void> _register() async {
    final weakness = pinWeakness(_pin.text);
    if (_name.text.trim().length < 2) return showInfo(context, 'Entrez votre nom.');
    if (weakness != null) return showInfo(context, weakness);
    if (_pin.text != _pin2.text) return showInfo(context, 'Les deux PIN ne sont pas identiques.');
    await _auth.register(otpToken: _otpToken!, fullName: _name.text.trim(), pin: _pin.text);
  }

  Future<void> _link() => _auth.linkDevice(otpToken: _otpToken!, pin: _pin.text);

  void _startForgot() {
    _pin.clear();
    _pin2.clear();
    setState(() => _step = _Step.forgot);
  }

  /// Si aucun garant n'est nécessaire, l'utilisateur est connecté ; sinon l'app passe à l'attente.
  Future<void> _requestReset() async {
    final weakness = pinWeakness(_pin.text);
    if (weakness != null) return showInfo(context, weakness);
    if (_pin.text != _pin2.text) return showInfo(context, 'Les deux PIN ne sont pas identiques.');
    await _auth.requestPinReset(otpToken: _otpToken!, newPin: _pin.text);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.phone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = _Step.phone);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const BrandMark(size: 30),
          leading: _step == _Step.phone ? null : BackButton(onPressed: () => setState(() => _step = _Step.phone)),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: switch (_step) {
              _Step.phone => _phoneStep(context),
              _Step.code => _codeStep(context),
              _Step.register => _registerStep(context),
              _Step.link => _linkStep(context),
              _Step.forgot => _forgotStep(context),
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(BuildContext context) => [
    ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: const Illustration('ensemble', height: 190, semanticLabel: 'Des membres cotisent ensemble'),
    ),
    const SizedBox(height: 24),
    Text('Bienvenue', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8),
    Text(
      'Chaque cotisation, vérifiable. Entrez votre numéro de téléphone pour commencer.',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Brand.ink.withValues(alpha: 0.7)),
    ),
    const SizedBox(height: 24),
    TextField(
      key: const Key('phone'),
      controller: _phone,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Numéro de téléphone',
        hintText: '099 123 4567',
        prefixIcon: Icon(Icons.phone),
      ),
    ),
    const SizedBox(height: 16),
    BusyButton(label: 'Recevoir un code par SMS', icon: Icons.sms, onPressed: _sendCode),
    const SizedBox(height: 24),
    Text(noCustodyNotice, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
  ];

  List<Widget> _codeStep(BuildContext context) => [
    Text('Code reçu par SMS', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    Text('Envoyé au ${_phone.text.trim()}. Il expire dans 5 minutes.'),
    const SizedBox(height: 24),
    TextField(
      key: const Key('code'),
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, letterSpacing: 10),
      decoration: const InputDecoration(counterText: ''),
    ),
    const SizedBox(height: 16),
    BusyButton(label: 'Valider', onPressed: _verifyCode),
    TextButton(onPressed: _sendCode, child: const Text('Renvoyer un code')),
  ];

  List<Widget> _registerStep(BuildContext context) => [
    Text('Créer votre compte', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 24),
    TextField(
      key: const Key('name'),
      controller: _name,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Votre nom',
        hintText: 'tel que les membres vous connaissent',
        prefixIcon: Icon(Icons.person),
      ),
    ),
    const SizedBox(height: 16),
    PinField(key: const Key('pin'), controller: _pin, label: 'Choisissez un PIN (6 chiffres)'),
    const SizedBox(height: 12),
    PinField(key: const Key('pin2'), controller: _pin2, label: 'Retapez le PIN'),
    const SizedBox(height: 8),
    const Text("N'utilisez pas votre PIN mobile money."),
    const SizedBox(height: 16),
    BusyButton(label: 'Créer mon compte', onPressed: _register),
  ];

  List<Widget> _linkStep(BuildContext context) => [
    Text('Vous avez déjà un compte', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text('Entrez votre PIN Mchango pour utiliser ce téléphone. Votre ancien téléphone sera déconnecté.'),
    const SizedBox(height: 24),
    PinField(key: const Key('pin'), controller: _pin, label: 'PIN', autofocus: true),
    const SizedBox(height: 16),
    BusyButton(label: 'Continuer', onPressed: _link),
    const SizedBox(height: 8),
    TextButton(key: const Key('forgot_pin'), onPressed: _startForgot, child: const Text('PIN oublié ?')),
  ];

  List<Widget> _forgotStep(BuildContext context) => [
    Text('Choisir un nouveau PIN', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 8),
    const Text(
      'Si vous êtes dans une tontine, une personne du groupe (le président, ou un membre si vous '
      'êtes président) devra confirmer que c\'est bien vous. Elle recevra un SMS.',
    ),
    const SizedBox(height: 24),
    PinField(key: const Key('new_pin'), controller: _pin, label: 'Nouveau PIN (6 chiffres)', autofocus: true),
    const SizedBox(height: 12),
    PinField(key: const Key('new_pin2'), controller: _pin2, label: 'Retapez le nouveau PIN'),
    const SizedBox(height: 16),
    BusyButton(label: 'Demander un nouveau PIN', onPressed: _requestReset),
  ];
}
