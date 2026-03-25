import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app.dart';
import '../services/calendar_availability_service.dart';
import '../services/local_notification_service.dart';
import '../services/notification_reader_service.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class PostRegisterIntroScreen extends StatefulWidget {
  const PostRegisterIntroScreen({super.key});

  @override
  State<PostRegisterIntroScreen> createState() =>
      _PostRegisterIntroScreenState();
}

class _PostRegisterIntroScreenState extends State<PostRegisterIntroScreen> {
  int _step = 0;
  AppLifecycleListener? _appLifecycleListener;
  bool _waitingForNotificationReaderAccess = false;

  static const List<_RegisterIntroStep> _steps = <_RegisterIntroStep>[
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_presenting.svg',
      message:
          "Welcome to SpendAnt!\n\nWe'll help you handle the small\nstuff so your savings can grow big!",
      primaryLabel: 'Continue',
    ),
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_waving.svg',
      message:
          'To help us spot patterns in your\nspending, import a calendar .ics file\nso SpendAnt can understand your\nupcoming plans and routines.',
      primaryLabel: 'Import Calendar (.ics)',
      secondaryLabel: 'Skip',
    ),
    _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_idle.svg',
      message:
          'On Android, SpendAnt can send\nits own alerts and read Google Pay\nnotifications so purchases become\nexpenses automatically.',
      primaryLabel: 'Allow Notification Access',
      secondaryLabel: 'Skip',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(_handleAppResume());
      },
    );
  }

  @override
  void dispose() {
    _appLifecycleListener?.dispose();
    super.dispose();
  }

  Future<void> _openLocationPermissionIntro() async {
    if (!mounted) {
      return;
    }

    final routeArguments = ModalRoute.of(context)?.settings.arguments;
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.locationPermissionIntro,
      arguments: routeArguments,
    );
  }

  Future<void> _handleAppResume() async {
    if (!_waitingForNotificationReaderAccess ||
        !NotificationReaderService.isSupportedPlatform) {
      return;
    }

    final isEnabled = await NotificationReaderService.isAccessEnabled();
    if (!mounted || !isEnabled) {
      return;
    }

    _waitingForNotificationReaderAccess = false;
    await _showInfoDialog(
      'Google Pay notification reading is enabled. New purchases can now be imported automatically.',
    );
    await _openLocationPermissionIntro();
  }

  Future<void> _requestPostingPermission() async {
    if (kIsWeb) {
      await _showInfoDialog(
        'Notification permission is only available on mobile devices.',
      );
      return;
    }

    final alreadyGranted = await LocalNotificationService.ensurePermission();
    final grantedNow = alreadyGranted
        ? true
        : await LocalNotificationService.ensurePermission(promptIfNeeded: true);
    if (!mounted) {
      return;
    }

    final status = await Permission.notification.status;
    if (!grantedNow && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showInfoDialog(
        'SpendAnt alerts are blocked right now. You can enable them later from system settings.',
      );
      return;
    }

    if (!grantedNow) {
      await _showInfoDialog(
        'SpendAnt alert notifications were not enabled on this device.',
      );
    }
  }

  Future<void> _handleCalendarImport() async {
    final result = await CalendarAvailabilityService.instance.importSchedule();
    if (!mounted) {
      return;
    }

    switch (result.status) {
      case CalendarConnectionStatus.connected:
        final schedule = result.schedule!;
        final recurringLabel =
            '${schedule.recurringEventCount} recurring class${schedule.recurringEventCount == 1 ? '' : 'es'}';
        final oneTimeLabel =
            '${schedule.oneTimeEventCount} one-time event${schedule.oneTimeEventCount == 1 ? '' : 's'}';
        await _showInfoDialog(
          'Imported ${schedule.fileName}. SpendAnt found $recurringLabel and $oneTimeLabel.\n\n${result.message ?? 'Recurring classes can now block habit warnings during the student schedule window.'}',
        );
        return;
      case CalendarConnectionStatus.emptySchedule:
        await _showInfoDialog(
          result.message ??
              'That .ics file did not contain timed class events.',
        );
        return;
      case CalendarConnectionStatus.canceled:
      case CalendarConnectionStatus.notConnected:
        await _showInfoDialog(
          result.message ??
              'No class schedule was imported, so habit warnings will stay off until you add an .ics file.',
        );
        return;
      case CalendarConnectionStatus.invalidFile:
      case CalendarConnectionStatus.error:
        await _showInfoDialog(
          result.message ??
              'The selected .ics file could not be used as a class schedule.',
        );
        return;
      case CalendarConnectionStatus.unsupported:
        await _showInfoDialog(
          result.message ??
              'Class schedule import is not available on this device.',
        );
        return;
    }
  }

  Future<void> _handlePrimaryAction() async {
    if (_step == 0) {
      setState(() {
        _step = 1;
      });
      return;
    }

    if (_step == 1) {
      await _handleCalendarImport();
      setState(() {
        _step = 2;
      });
      return;
    }

    await _requestPostingPermission();
    if (!mounted) {
      return;
    }

    if (kIsWeb) {
      await _openLocationPermissionIntro();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      await _showInfoDialog(
        'Automatic Google Pay import is only available on Android.',
      );
      await _openLocationPermissionIntro();
      return;
    }

    final hasReaderAccess = await NotificationReaderService.isAccessEnabled();
    if (!mounted) {
      return;
    }

    if (hasReaderAccess) {
      await _openLocationPermissionIntro();
      return;
    }

    await _showInfoDialog(
      'Android also needs notification reading access to import Google Pay purchases. Enable it in the next screen.',
    );
    setState(() {
      _waitingForNotificationReaderAccess = true;
    });

    try {
      await NotificationReaderService.openAccessSettings();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _waitingForNotificationReaderAccess = false;
      });
      await _showInfoDialog(
        'The notification reader settings could not be opened on this device.',
      );
      await _openLocationPermissionIntro();
    }
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

  Future<void> _handleSecondaryAction() async {
    if (_step == 1) {
      setState(() {
        _step = 2;
      });
      return;
    }

    await _openLocationPermissionIntro();
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
                width: _step == 1 || _step == 2 ? 244 : 154,
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
