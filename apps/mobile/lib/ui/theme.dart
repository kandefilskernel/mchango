import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/l10n.dart';

/// Couleurs de la marque (les mêmes que tool/illustrations.py).
abstract final class Brand {
  static const green = Color(0xFF0F5E43);
  static const greenLight = Color(0xFF2E8B57);
  static const mint = Color(0xFFE3F1EA);
  static const gold = Color(0xFFF2B33D);
  static const goldDark = Color(0xFFC98A1B);
  static const ink = Color(0xFF1F2933);
  static const cream = Color(0xFFFFF8EC);
  static const surface = Color(0xFFF7F8F6);

  /// Dégradé des en-têtes : vert profond vers vert clair.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, greenLight],
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    primary: Brand.green,
    secondary: Brand.gold,
    surface: Brand.surface,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.surface,
    textTheme: base.textTheme
        .apply(bodyColor: Brand.ink, displayColor: Brand.ink)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: Brand.ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: Brand.ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: Brand.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Brand.ink),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.surface,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Brand.ink.withValues(alpha: 0.06)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.green,
        minimumSize: const Size.fromHeight(54),
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.green,
        minimumSize: const Size.fromHeight(54),
        shape: rounded,
        side: const BorderSide(color: Brand.green, width: 1.5),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Brand.ink.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.green, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selectedColor: Brand.mint,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Illustration de la marque (`assets/illustrations/<name>.svg`).
class Illustration extends StatelessWidget {
  const Illustration(this.name, {super.key, this.height, this.semanticLabel});

  final String name;
  final double? height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/illustrations/$name.svg',
    height: height,
    fit: BoxFit.contain,
    semanticsLabel: semanticLabel,
  );
}

/// Logo + nom.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.light = false});

  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SvgPicture.asset('assets/illustrations/logo.svg', height: size, semanticsLabel: 'Mchango'),
      SizedBox(width: size * 0.3),
      Text(
        t('Mchango'),
        style: TextStyle(
          fontSize: size * 0.62,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: light ? Colors.white : Brand.green,
        ),
      ),
    ],
  );
}
