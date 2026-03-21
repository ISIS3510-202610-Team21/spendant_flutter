import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/auth_memory_store.dart';
import '../services/fingerprint_login_service.dart';
import '../widgets/auth_chrome.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    final authState = await AuthMemoryStore.loadGreetingState();

    if (!mounted) {
      return;
    }

    if (authState.canUseFingerprintLogin) {
      final result = await FingerprintLoginService.authenticate(
        Navigator.of(context),
      );
      if (!mounted || result.didAuthenticate) {
        return;
      }

      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      return;
    }

    final nextRoute = authState.hasSavedSession
        ? AppRoutes.home
        : AppRoutes.login;

    Navigator.of(context).pushReplacementNamed(nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AntAsset('web/ant/ant_coin.svg', height: 165),
            const SizedBox(height: 10),
            Text(
              'Loading...',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
