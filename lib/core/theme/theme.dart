import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

/// Provider to manage the active ThemeMode (Light or Dark).
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class AppTheme {
  AppTheme._();

  // Slate & Cobalt Palette definitions
  static const Color slateDarkBg = Color(0xFF0F172A);
  static const Color slateDarkSurface = Color(0xFF1E293B);
  static const Color slateDarkBorder = Color(0xFF334155);
  static const Color slateLightBg = Color(0xFFF8FAFC);
  static const Color slateLightSurface = Color(0xFFFFFFFF);
  static const Color slateLightBorder = Color(0xFFE2E8F0);

  static const Color cobaltBlue = Color(0xFF2563EB);
  static const Color cobaltBlueDark = Color(0xFF1D4ED8);
  static const Color teal = Color(0xFF0D9488);
  static const Color tealDark = Color(0xFF0F766E);
  static const Color coral = Color(0xFFF43F5E);

  /// Sleek Light Theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: cobaltBlue,
        secondary: teal,
        error: coral,
        background: slateLightBg,
        surface: slateLightSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: Color(0xFF0F172A),
        onSurface: Color(0xFF0F172A),
        outline: slateLightBorder,
      ),
      scaffoldBackgroundColor: slateLightBg,
      cardTheme: CardThemeData(
        color: slateLightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: slateLightBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: slateLightBg,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
        titleMedium: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFF334155)),
        bodyLarge: GoogleFonts.outfit(fontSize: 16, color: const Color(0xFF0F172A)),
        bodyMedium: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF475569)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slateLightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateLightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateLightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cobaltBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF475569)),
      ),
    );
  }

  /// Sleek Dark Theme (Slate/Glassmorphic Style)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: cobaltBlue,
        secondary: teal,
        error: coral,
        background: slateDarkBg,
        surface: slateDarkSurface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onBackground: Color(0xFFF8FAFC),
        onSurface: Color(0xFFF8FAFC),
        outline: slateDarkBorder,
      ),
      scaffoldBackgroundColor: slateDarkBg,
      cardTheme: CardThemeData(
        color: slateDarkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: slateDarkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: slateDarkBg,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFF8FAFC)),
        titleTextStyle: TextStyle(
          color: Color(0xFFF8FAFC),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        titleLarge: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w600, color: const Color(0xFFF8FAFC)),
        titleMedium: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w500, color: const Color(0xFFCBD5E1)),
        bodyLarge: GoogleFonts.outfit(fontSize: 16, color: const Color(0xFFF8FAFC)),
        bodyMedium: GoogleFonts.outfit(fontSize: 14, color: const Color(0xFF94A3B8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slateDarkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateDarkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slateDarkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cobaltBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
    );
  }
}
