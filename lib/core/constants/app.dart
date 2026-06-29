import 'package:fatoora/core/constants/color.dart';
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light({String fontFamily = 'Roboto'}) {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColor.primaryColor,
      onPrimary: Colors.white,
      secondary: AppColor.secondaryColor,
      onSecondary: Colors.white,
      error: AppColor.error,
      onError: Colors.white,
      surface: AppColor.surface,
      onSurface: Color(0xFF17213B),
      surfaceContainerLow: Color(0xFFF3F5F9),
      surfaceContainerHighest: Color(0xFFE9EDF4),
      onSurfaceVariant: Color(0xFF667085),
      outline: Color(0xFF98A2B3),
      outlineVariant: Color(0xFFE1E5ED),
      shadow: Color(0x1A18223B),
      scrim: Color(0x66000000),
      inverseSurface: Color(0xFF222B3A),
      onInverseSurface: Colors.white,
      inversePrimary: Color(0xFFFFB3B9),
      tertiary: AppColor.tertiaryColor,
      onTertiary: Colors.white,
    );
    return _build(
      scheme: scheme,
      scaffoldBackground: AppColor.background,
      fontFamily: fontFamily,
    );
  }

  static ThemeData dark({String fontFamily = 'Roboto'}) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFF7D88),
      onPrimary: Color(0xFF4F0710),
      secondary: Color(0xFF8ED6F2),
      onSecondary: Color(0xFF003545),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: AppColor.darkSurface,
      onSurface: Color(0xFFF0F2F6),
      surfaceContainerLow: Color(0xFF171C25),
      surfaceContainerHighest: AppColor.darkSurfaceRaised,
      onSurfaceVariant: Color(0xFFB7C0CE),
      outline: Color(0xFF7D8796),
      outlineVariant: AppColor.darkBorder,
      shadow: Color(0x66000000),
      scrim: Color(0x99000000),
      inverseSurface: Color(0xFFF0F2F6),
      onInverseSurface: Color(0xFF171B22),
      inversePrimary: AppColor.primaryColor,
      tertiary: Color(0xFFFFAFC7),
      onTertiary: Color(0xFF501128),
    );
    return _build(
      scheme: scheme,
      scaffoldBackground: AppColor.darkBackground,
      fontFamily: fontFamily,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required String fontFamily,
  }) {
    final dark = scheme.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
    );
    final textTheme = base.textTheme
        .apply(
          fontFamily: fontFamily,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55),
        );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainerHighest : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColor.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColor.primaryColor.withValues(alpha: .35),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColor.primaryColor,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: buttonShape,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        modalBarrierColor: scheme.scrim,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? scheme.surfaceContainerHighest
            : AppColor.primaryDark,
        contentTextStyle: TextStyle(
          color: dark ? scheme.onSurface : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        dividerThickness: 1,
        dataTextStyle: textTheme.bodyMedium,
        headingTextStyle: textTheme.labelLarge,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}

final ThemeData themeEnglish = AppTheme.light();
final ThemeData themeArabic = AppTheme.light(fontFamily: 'Cairo');
final ThemeData darkThemeEnglish = AppTheme.dark();
final ThemeData darkThemeArabic = AppTheme.dark(fontFamily: 'Cairo');
