import 'package:flutter/material.dart';
import 'package:fatoora/core/constants/color.dart';

final ThemeData themeEnglish = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: "Roboto",
  primaryColor: AppColor.primaryColor,
  scaffoldBackgroundColor: AppColor.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColor.primaryColor,
    brightness: Brightness.light,
  ),

  // 👇 AppBar
  appBarTheme: AppBarTheme(
    backgroundColor: AppColor.primaryColor,
    foregroundColor: Colors.white,
    elevation: 3,
    shadowColor: Colors.black.withValues(alpha: 0.15),
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    titleTextStyle: const TextStyle(
      fontFamily: "Roboto",
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
  ),

  // 👇 Text
  textTheme: const TextTheme(
    displayLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
    headlineLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
    titleLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    bodyLarge: TextStyle(
      height: 1.6,
      color: AppColor.grey,
      fontWeight: FontWeight.w500,
      fontSize: 14,
    ),
    bodyMedium: TextStyle(color: AppColor.grey, fontSize: 12),
    labelLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
  ),

  // 👇 Buttons
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => states.contains(WidgetState.disabled)
            ? AppColor.primaryColor.withValues(alpha: 0.3)
            : AppColor.primaryColor,
      ),
      foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      padding: WidgetStateProperty.all<EdgeInsets>(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.all<Color>(AppColor.primaryColor),
      overlayColor: WidgetStateProperty.all<Color>(
        AppColor.primaryColor.withValues(alpha: 0.1),
      ),
    ),
  ),

  // 👇 Inputs
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColor.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColor.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColor.primaryColor, width: 1.5),
    ),
    hintStyle: const TextStyle(color: AppColor.grey, fontSize: 13),
  ),

  // 👇 Misc
  iconTheme: const IconThemeData(color: AppColor.primaryColor),

  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppColor.primaryDark,
    contentTextStyle: const TextStyle(color: Colors.white),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),

  cardTheme: CardThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 2,
    margin: const EdgeInsets.all(8),
    surfaceTintColor: Colors.transparent,
    color: AppColor.surface,
  ),
);

final ThemeData themeArabic = themeEnglish.copyWith(
  textTheme: themeEnglish.textTheme.apply(fontFamily: 'Cairo'),
);
