import 'package:flutter/material.dart';

/// Semantic colors mapped from the light and dark MasterGo handoff.
class AppColors {
  const AppColors(this.dark);
  final bool dark;
  static AppColors of(BuildContext context) =>
      AppColors(Theme.of(context).brightness == Brightness.dark);
  Color get background => Color(dark ? 0xFF0E1718 : 0xFFF5F7F5);
  Color get surface => Color(dark ? 0xFF172426 : 0xFFFFFFFF);
  Color get raised => Color(dark ? 0xFF213235 : 0xFFF1F5F3);
  Color get footer => Color(dark ? 0xFF121F20 : 0xFFFFFFFF);
  Color get hero => Color(dark ? 0xFF153D38 : 0xFF142D36);
  Color get heroText => Color(dark ? 0xFFEAF4F1 : 0xFFFFFFFF);
  Color get heroMuted => Color(dark ? 0xFFB4D1C6 : 0xFFC6E1D9);
  Color get primary => Color(dark ? 0xFF64DDB4 : 0xFF086E61);
  Color get onPrimary => Color(dark ? 0xFF082A23 : 0xFFFFFFFF);
  Color get text => Color(dark ? 0xFFEAF4F1 : 0xFF142D36);
  Color get secondary => Color(dark ? 0xFFA4BBB4 : 0xFF647572);
  Color get border => Color(dark ? 0xFF33494B : 0xFFDFE7E3);
  Color get fieldBorder => Color(dark ? 0xFF6D8780 : 0xFFDFE7E3);
  Color get soft => Color(dark ? 0xFF1A3B32 : 0xFFE8F4ED);
  Color get mint => Color(dark ? 0xFF64DDB4 : 0xFFD9F7DD);
  Color get warning => Color(dark ? 0xFFF2C078 : 0xFF96611D);
  Color get warningSoft => Color(dark ? 0xFF3B2E1D : 0xFFFFF2DA);
}

ThemeData opcTheme(Brightness brightness) {
  final c = AppColors(brightness == Brightness.dark);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.primary,
        brightness: brightness,
      ).copyWith(
        primary: c.primary,
        onPrimary: c.onPrimary,
        surface: c.surface,
        onSurface: c.text,
        outline: c.border,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: c.background,
    textTheme: base.textTheme
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 30,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
          headlineSmall: TextStyle(
            fontSize: 23,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
          titleLarge: TextStyle(
            fontSize: 21,
            height: 1.45,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
          titleSmall: TextStyle(
            fontSize: 14,
            height: 1.55,
            fontWeight: FontWeight.w600,
            color: c.text,
          ),
          bodyMedium: TextStyle(fontSize: 13, height: 1.7, color: c.text),
          bodySmall: TextStyle(fontSize: 11, height: 1.65, color: c.secondary),
          labelSmall: TextStyle(fontSize: 10, height: 1.6, color: c.secondary),
        ),
    dividerColor: c.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: c.secondary, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        disabledBackgroundColor: c.dark
            ? const Color(0xFF263B35)
            : const Color(0xFFDFE8E3),
        disabledForegroundColor: c.dark
            ? const Color(0xFF849B93)
            : const Color(0xFF84938F),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        backgroundColor: c.surface,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: c.surface,
      selectedColor: c.soft,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.hero,
      contentTextStyle: TextStyle(color: c.heroText),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      showDragHandle: true,
    ),
  );
}
