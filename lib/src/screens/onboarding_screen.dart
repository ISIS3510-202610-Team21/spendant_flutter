import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/auth_memory_store.dart';
import '../services/fingerprint_login_service.dart';
import '../widgets/auth_chrome.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final Future<AuthGreetingState> _greetingFuture;
  bool _isAuthenticatingWithFingerprint = false;
  String? _authStatusText;

  @override
  void initState() {
    super.initState();
    _greetingFuture = AuthMemoryStore.loadGreetingState();
  }

  void _openLoginFlow() {
    setState(() {
      _authStatusText = null;
    });
    Navigator.of(context).pushNamed(AppRoutes.login);
  }

  Future<void> _openFingerprint() async {
    if (_isAuthenticatingWithFingerprint) {
      return;
    }

    final authState = await _greetingFuture;
    if (!mounted) {
      return;
    }

    if (!authState.canUseFingerprintLogin) {
      Navigator.of(context).pushNamed(AppRoutes.login);
      return;
    }

    setState(() {
      _isAuthenticatingWithFingerprint = true;
      _authStatusText = null;
    });

    final result = await FingerprintLoginService.authenticate(
      Navigator.of(context),
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _isAuthenticatingWithFingerprint = false;
      _authStatusText = result.didAuthenticate ? null : result.message;
    });

    if (result.didAuthenticate || result.message == null) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Positioned(
                left: -28,
                bottom: -56,
                child: AntAsset('web/ant/ant_login.svg', height: 460),
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
                          label: _isAuthenticatingWithFingerprint
                              ? 'Authenticating...'
                              : 'Login with FingerPrint',
                          width: 208,
                          onPressed: _isAuthenticatingWithFingerprint
                              ? () {}
                              : _openFingerprint,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _openLoginFlow,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            textStyle: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Login with other User'),
                        ),
                        if (_authStatusText != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _authStatusText!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                        ],
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
    if (state == null || !state.hasSavedSession) {
      return 'Welcome to SpendAnt.';
    }

    final username = state.username?.trim();
    if (username == null || username.isEmpty) {
      return 'Welcome back.';
    }

    return 'Hi $username.';
  }
}
