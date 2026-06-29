import 'package:flutter/material.dart';

class AppColor {
  static const Color primaryColor = Color(0xFFB7212E);
  static const Color primaryDark = Color(0xFF8E1A23);
  static const Color primaryLight = Color(0xFFF2D1D4);
  static const Color secondaryColor = Color(0xFF003F5C);
  static const Color tertiaryColor = Color(0xFF83334C);
  static const Color accentYellow = Color(0xFFFFC107);
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFE53935);
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF424242);
  static const Color grey = Color(0xFF8E8E8E);
  static const Color lightGrey = Color(0xFFD6D6D6);
  static const Color background = Color(0xFFF8F9FD);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFBDBDBD);
  static const Color darkBackground = Color(0xFF11151C);
  static const Color darkSurface = Color(0xFF191F29);
  static const Color darkSurfaceRaised = Color(0xFF202735);
  static const Color darkBorder = Color(0xFF303948);

  static const LinearGradient mainGradient = LinearGradient(
    colors: [Color(0xFFB7212E), Color(0xFF8E1A23)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

extension FatooraThemeColors on BuildContext {
  Color get appBackground => Theme.of(this).scaffoldBackgroundColor;
  Color get appSurface => Theme.of(this).colorScheme.surface;
  Color get appSurfaceMuted => Theme.of(this).colorScheme.surfaceContainerLow;
  Color get appSurfaceRaised =>
      Theme.of(this).colorScheme.surfaceContainerHighest;
  Color get appText => Theme.of(this).colorScheme.onSurface;
  Color get appMutedText => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get appBorder => Theme.of(this).colorScheme.outlineVariant;
}
