import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/auth_memory_store.dart';
import '../widgets/auth_chrome.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final Future<AuthGreetingState> _greetingFuture;

  @override
  void initState() {
    super.initState();
    _greetingFuture = AuthMemoryStore.loadGreetingState();
  }

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
                bottom: -300,
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
                        FutureBuilder<AuthGreetingState>(
                          future: _greetingFuture,
                          builder: (context, snapshot) {
                            final greeting = _buildGreeting(snapshot.data);
                            return Text(
                              greeting,
                              style: GoogleFonts.nunito(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            );
                          },
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
                        const SizedBox(height: 16),
                        // Demo buttons for new views
                        GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed(AppRoutes.fingerprintAuth),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'View: Fingerprint Auth',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pushNamed(AppRoutes.setGoal),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'View: Set Goal',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                          ),
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

  String _buildGreeting(AuthGreetingState? state) {
    if (state == null || !state.hasLoggedInBefore) {
      return 'Welcome to SpendAnt.';
    }

    final username = state.username?.trim();
    if (username == null || username.isEmpty) {
      return 'Welcome back.';
    }

    return 'Hi $username.';
  }
}
