import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppPalette {
  static const green = Color(0xFF44C669);
  static const field = Color(0xFFE0FFE9);
  static const ink = Color(0xFF000000);
  static const fieldHint = Color(0xFF5E5E5E);
  static const white = Colors.white;
  static const amber = Color(0xFFFCC34D);
  static const amberField = Color(0xFFFCE8AB);
  static const gray = Color(0xFFF5F5F5);
  static const food = Color(0xFF297DE7);
  static const transport = Color(0xFFFF632D);
  static const services = Color(0xFFF3BE28);
  static const other = Color(0xFFFD8D8C);
  static const expenseRed = Color(0xFFF04C4C);
  static const cardBorderGray = Color(0xFFD0D0D0);
  static const notificationBadge = Color(0xFFFF7A2F);
}

/// Pre-computed const [BorderRadius] values for use across the UI.
/// Using these constants instead of [BorderRadius.circular] inside [build]
/// methods avoids allocating a new object on every rebuild.
abstract final class AppRadius {
  static const pill = BorderRadius.all(Radius.circular(999));
  static const card = BorderRadius.all(Radius.circular(14));
  static const dialog = BorderRadius.all(Radius.circular(24));
  static const large = BorderRadius.all(Radius.circular(32));
  static const input = BorderRadius.all(Radius.circular(12));
  static const chip = BorderRadius.all(Radius.circular(10));
  static const small = BorderRadius.all(Radius.circular(3));
  static const cardTile = BorderRadius.all(Radius.circular(2));
}

abstract final class AppHeaderMetrics {
  static const double top = 58;

  static EdgeInsets padding({
    double horizontal = 12,
    double top = AppHeaderMetrics.top,
    double bottom = 14,
  }) {
    return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
  }
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
          fontSize: 65,
          height: 0.95,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: AppPalette.ink,
        ),
        displaySmall: GoogleFonts.recursive(
          fontSize: 45,
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
          borderRadius: AppRadius.small,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.small,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.small,
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
            borderRadius: AppRadius.card,
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
