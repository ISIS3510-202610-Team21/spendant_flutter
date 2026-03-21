import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class LocationPermissionIntroScreen extends StatefulWidget {
  const LocationPermissionIntroScreen({super.key});

  @override
  State<LocationPermissionIntroScreen> createState() =>
      _LocationPermissionIntroScreenState();
}

class _LocationPermissionIntroScreenState
    extends State<LocationPermissionIntroScreen> {
  bool _isRequestingPermission = false;

  Future<void> _finishFlow() async {
    final navigator = Navigator.of(context);
    final args = ModalRoute.of(context)?.settings.arguments;
    final postAuthNavigationArgs = args is PostAuthNavigationArgs ? args : null;
    final redirect = postAuthNavigationArgs?.redirect;

    await AuthMemoryStore.markLocationPermissionPromptCompleted();
    if (redirect != null) {
      await AppNavigationService.openRedirect(redirect);
      return;
    }

    navigator.pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<void> _handleSkip() async {
    if (_isRequestingPermission) {
      return;
    }

    await _finishFlow();
  }

  Future<void> _handleAllowLocationAccess() async {
    if (_isRequestingPermission) {
      return;
    }

    setState(() {
      _isRequestingPermission = true;
    });

    var infoMessage = '';

    try {
      if (kIsWeb) {
        infoMessage =
            'Location permission is only available on mobile and desktop apps.';
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          if (mounted) {
            setState(() {
              _isRequestingPermission = false;
            });
          }
          await _finishFlow();
          return;
        }

        if (permission == LocationPermission.deniedForever) {
          infoMessage =
              'Location access is blocked in system settings. You can enable it later if you want smarter place suggestions.';
        } else {
          infoMessage =
              'Location access was not enabled. You can allow it later if you want smarter place suggestions.';
        }
      }
    } catch (_) {
      infoMessage =
          'Location permission could not be requested right now. You can enable it later from device settings.';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isRequestingPermission = false;
    });

    await _showInfoDialog(infoMessage);
    await _finishFlow();
  }

  Future<void> _showInfoDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GreenScreenScaffold(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Text(
                'Want smarter suggestions? Allow location access so SpendAnt can detect nearby places, organize your spending better, and make each record faster and more accurate.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 26),
              const AntAsset('web/ant/ant_standing.svg', height: 250),
              const SizedBox(height: 30),
              BlackPrimaryButton(
                label: _isRequestingPermission
                    ? 'Requesting...'
                    : 'Allow Location Access',
                width: 244,
                height: 44,
                onPressed: _handleAllowLocationAccess,
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _handleSkip,
                style: TextButton.styleFrom(foregroundColor: AppPalette.ink),
                child: Text(
                  'Skip',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
              ),
              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
