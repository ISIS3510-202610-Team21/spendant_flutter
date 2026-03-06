import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../widgets/auth_chrome.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  void _openAuth(BuildContext context) {
    Navigator.of(context).pushNamed(AppRoutes.loading);
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Positioned(
                left: -175,
                bottom: -225,
                child: AntAsset('web/ant/Standing.svg', height: 700),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 120),
                        const SpendAntWordmark(),
                        const SizedBox(height: 112),
                        Text(
                          'Hi Bob.',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 18),
                        BlackPrimaryButton(
                          label: 'Login with FingerPrint',
                          width: 208,
                          onPressed: () => _openAuth(context),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => _openAuth(context),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            textStyle: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Login with other User'),
                        ),
                        SizedBox(height: constraints.maxHeight * 0.34),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
