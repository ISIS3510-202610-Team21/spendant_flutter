import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/auth_chrome.dart';
import '../theme/spendant_theme.dart';
import '../../app.dart'; // Importante para las rutas

class FingerprintAuthScreen extends StatelessWidget {
  const FingerprintAuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SpendAntWordmark(large: false),
          const SizedBox(height: 60),
          Text(
            'Touch the sensor',
            style: GoogleFonts.nunito(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 40),
          GestureDetector(
            // Cambiamos el pop por una navegación al Onboarding/Home para el demo
            onTap: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.onboarding, (route) => false);
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppPalette.field,
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.ink, width: 2),
              ),
              child: const Icon(
                Icons.fingerprint,
                size: 80,
                color: AppPalette.ink,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Use your fingerprint to log in safely',
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: AppPalette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
