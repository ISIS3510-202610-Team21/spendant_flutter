import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class PostRegisterIntroScreen extends StatefulWidget {
  const PostRegisterIntroScreen({super.key});

  @override
  State<PostRegisterIntroScreen> createState() => _PostRegisterIntroScreenState();
}

class _PostRegisterIntroScreenState extends State<PostRegisterIntroScreen> {
  int _step = 0;

  static const List<_RegisterIntroStep> _steps = <_RegisterIntroStep>[
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_presenting.svg',
      message:
          "Welcome to SpendAnt!\n\nWe’ll help you handle the small\nstuff so your savings can grow big!",
      primaryLabel: 'Continue',
    ),
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_waving.svg',
      message:
          "To help us spot patterns in your\nspending, like that recurring\nFriday lunch or upcoming travel,\nwe’d love to sync with your\ncalendar.",
      primaryLabel: 'Sync Calendar',
      secondaryLabel: 'Skip',
    ),
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_idle.svg',
      message:
          'Want instant insights? Allow\nnotification access for Google Pay,\nand SpendAnt will categorize your\nspending the second it happens.',
      primaryLabel: 'Allow Notification Access',
      secondaryLabel: 'Skip',
    ),
  ];

  Future<void> _goHome() async {
    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_step == 0) {
      setState(() {
        _step = 1;
      });
      return;
    }

    if (_step == 1) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calendar sync will be available in a later update.'),
        ),
      );
      setState(() {
        _step = 2;
      });
      return;
    }

    if (!kIsWeb) {
      final status = await Permission.notification.request();
      if (!mounted) {
        return;
      }

      if (status.isPermanentlyDenied || status.isRestricted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification access is blocked. Open settings if you want to enable it later.',
            ),
          ),
        );
        await openAppSettings();
      } else if (!status.isGranted && !status.isLimited) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification access was not enabled.'),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission is only available on mobile devices.',
          ),
        ),
      );
    }

    await _goHome();
  }

  Future<void> _handleSecondaryAction() async {
    if (_step == 1) {
      setState(() {
        _step = 2;
      });
      return;
    }

    await _goHome();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];

    return GreenScreenScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Text(
                step.message,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 26),
              AntAsset(step.antAssetPath, height: 240),
              const SizedBox(height: 28),
              BlackPrimaryButton(
                label: step.primaryLabel,
                width: _step == 2 ? 244 : 154,
                height: 44,
                onPressed: _handlePrimaryAction,
              ),
              if (step.secondaryLabel != null) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _handleSecondaryAction,
                  style: TextButton.styleFrom(foregroundColor: AppPalette.ink),
                  child: Text(
                    step.secondaryLabel!,
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.ink,
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterIntroStep {
  const _RegisterIntroStep({
    required this.antAssetPath,
    required this.message,
    required this.primaryLabel,
    this.secondaryLabel,
  });

  final String antAssetPath;
  final String message;
  final String primaryLabel;
  final String? secondaryLabel;
}
