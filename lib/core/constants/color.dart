import 'package:flutter/material.dart';

class AppColor {
  // 🔴 Primary brand color (main red)
  static const Color primaryColor = Color(0xFFB7212E);

  // 🩸 Darker shade of the primary color (for pressed states, shadows)
  static const Color primaryDark = Color(0xFF8E1A23);

  // 🌹 Lighter tint of primary color (for hover/focus/soft backgrounds)
  static const Color primaryLight = Color(0xFFF2D1D4);

  // 🔵 Secondary color (calm complementary tone to red)
  static const Color secondaryColor = Color(0xFF003F5C);

  // 🟣 Tertiary color (slightly warmer accent for variety)
  static const Color tertiaryColor = Color(0xFF83334C);

  // 💛 Accent color (for highlights, alerts, or active states)
  static const Color accentYellow = Color(0xFFFFC107);

  // 🟢 Success / Green tone
  static const Color success = Color(0xFF4CAF50);

  // 🔴 Error / Red tone
  static const Color error = Color(0xFFE53935);

  // ⚫ Neutral shades
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF424242);
  static const Color grey = Color(0xFF8E8E8E);
  static const Color lightGrey = Color(0xFFD6D6D6);

  // 🩶 Background and surface
  static const Color background = Color(0xFFF8F9FD);
  static const Color surface = Colors.white;

  // 🩵 Borders, dividers
  static const Color border = Color(0xFFBDBDBD);

  // 🌈 Gradients or multi-tone blends
  static const LinearGradient mainGradient = LinearGradient(
    colors: [Color(0xFFB7212E), Color(0xFF8E1A23)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
