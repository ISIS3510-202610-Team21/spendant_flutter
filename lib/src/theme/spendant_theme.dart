import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppPalette {
  static const green = Color(0xFF44C669);
  static const field = Color(0xFFC8DDC8);
  static const ink = Color(0xFF000000);
  static const fieldHint = Color(0xFF5E5E5E);
  static const white = Colors.white;
}

abstract final class SpendAntTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.green,
      primary: AppPalette.green,
      secondary: AppPalette.green,
      surface: AppPalette.green,
      onSurface: AppPalette.ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.green,
    );

    final nunitoTextTheme = GoogleFonts.nunitoTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: nunitoTextTheme.copyWith(
        displayLarge: GoogleFonts.recursive(
          fontSize: 41,
          height: 0.95,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: AppPalette.ink,
        ),
        displaySmall: GoogleFonts.recursive(
          fontSize: 34,
          height: 0.95,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: AppPalette.ink,
        ),
        headlineMedium: GoogleFonts.nunito(
          fontSize: 18,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: AppPalette.ink,
        ),
        bodyLarge: GoogleFonts.nunito(
          fontSize: 16,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: AppPalette.ink,
        ),
        bodyMedium: GoogleFonts.nunito(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: AppPalette.ink,
        ),
        labelLarge: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppPalette.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.field,
        hintStyle: GoogleFonts.nunito(
          color: AppPalette.fieldHint,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: AppPalette.ink, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: AppPalette.ink,
          foregroundColor: AppPalette.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
