import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../services/calendar_availability_service.dart';
import '../services/local_notification_service.dart';
import '../services/notification_reader_service.dart';
import '../services/post_auth_navigation.dart';
import '../theme/spendant_theme.dart';
import '../widgets/auth_chrome.dart';

class PostRegisterIntroScreen extends StatefulWidget {
  const PostRegisterIntroScreen({super.key});

  @override
  State<PostRegisterIntroScreen> createState() =>
      _PostRegisterIntroScreenState();
}

class _PostRegisterIntroScreenState extends State<PostRegisterIntroScreen> {
  int _stepIndex = 0;
  AppLifecycleListener? _appLifecycleListener;
  bool _didResolveFlow = false;
  bool _waitingForNotificationReaderAccess = false;
  bool? _postingPermissionEnabled;
  bool? _notificationReaderEnabled;
  late PermissionsIntroArgs _flowArgs;
  late List<PermissionsIntroStep> _visibleSteps;

  static const Map<PermissionsIntroStep, _RegisterIntroStep>
  _steps = <PermissionsIntroStep, _RegisterIntroStep>{
    PermissionsIntroStep.welcome: _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_presenting.svg',
      message:
          "Welcome to SpendAnt!\n\nWe'll help you handle the small\nstuff so your savings can grow big!",
      primaryLabel: 'Continue',
      buttonWidth: 154,
    ),
    PermissionsIntroStep.calendar: _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_waving.svg',
      message:
          'To help us spot patterns in your\nspending, import a calendar .ics file\nso SpendAnt can understand your\nupcoming plans and routines.',
      primaryLabel: 'Import Calendar (.ics)',
      secondaryLabel: 'Skip',
      buttonWidth: 244,
    ),
    PermissionsIntroStep.notifications: _RegisterIntroStep(
      antAssetPath: 'web/ant/ant_idle.svg',
      message:
          'On Android, SpendAnt can send\nits own alerts and connect to\nnotification access when you allow it.\nUse this step to review or change\nthose permissions if needed.',
      primaryLabel: 'Allow Notification Access',
      secondaryLabel: 'Skip',
      buttonWidth: 244,
    ),
  };

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(_handleAppResume());
      },
    );
    unawaited(_refreshNotificationPermissionStatus());
  }

  @override
  void dispose() {
    _appLifecycleListener?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didResolveFlow) {
      return;
    }

    _flowArgs = _resolveFlowArgs(ModalRoute.of(context)?.settings.arguments);
    _visibleSteps = _buildVisibleSteps(_flowArgs);
    if (_visibleSteps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_completeFlow());
      });
    } else {
      final configuredIndex = _visibleSteps.indexOf(_flowArgs.initialStep);
      _stepIndex = configuredIndex >= 0 ? configuredIndex : 0;
    }
    _didResolveFlow = true;
  }

  PermissionsIntroArgs _resolveFlowArgs(Object? arguments) {
    if (arguments is PermissionsIntroArgs) {
      return arguments;
    }

    if (arguments is PostAuthNavigationArgs) {
      return PermissionsIntroArgs.fullOnboarding(redirect: arguments.redirect);
    }

    return const PermissionsIntroArgs.fullOnboarding();
  }

  List<PermissionsIntroStep> _buildVisibleSteps(PermissionsIntroArgs flowArgs) {
    final steps = <PermissionsIntroStep>[];
    if (flowArgs.showWelcomeStep) {
      steps.add(PermissionsIntroStep.welcome);
    }
    if (flowArgs.showCalendarStep) {
      steps.add(PermissionsIntroStep.calendar);
    }
    if (flowArgs.showNotificationStep) {
      steps.add(PermissionsIntroStep.notifications);
    }
    return steps;
  }

  PermissionsIntroStep get _currentStepType => _visibleSteps[_stepIndex];

  Future<void> _openLocationPermissionIntro() async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.locationPermissionIntro,
      arguments: _postAuthNavigationArgs,
    );
  }

  Future<void> _handleAppResume() async {
    await _refreshNotificationPermissionStatus();

    if (!_waitingForNotificationReaderAccess ||
        !NotificationReaderService.isSupportedPlatform) {
      return;
    }

    final isEnabled = await NotificationReaderService.isAccessEnabled();
    if (!mounted) {
      return;
    }

    _waitingForNotificationReaderAccess = false;
    if (!isEnabled) {
      await _showInfoDialog(
        'SpendAnt still cannot read supported notifications on this device. Turn on SpendAnt in that Android screen and try again.',
      );
      return;
    }

    await _showInfoDialog(
      'Notification reading is enabled. New supported purchases can now be imported automatically.',
    );
    await _advanceOrCompleteFlow();
  }

  Future<void> _refreshNotificationPermissionStatus() async {
    if (kIsWeb) {
      return;
    }

    final postingEnabled = await LocalNotificationService.ensurePermission();
    final readerEnabled = NotificationReaderService.isSupportedPlatform
        ? await NotificationReaderService.isAccessEnabled()
        : null;
    if (!mounted) {
      return;
    }

    setState(() {
      _postingPermissionEnabled = postingEnabled;
      _notificationReaderEnabled = readerEnabled;
    });
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

    if (alreadyGranted) {
      await _refreshNotificationPermissionStatus();
      await _showInfoDialog(
        'SpendAnt alert notifications are already enabled on this device.',
      );
      return;
    }

    final status = await Permission.notification.status;
    if (!grantedNow && (status.isPermanentlyDenied || status.isRestricted)) {
      await _showInfoDialog(
        'SpendAnt alerts are blocked right now. SpendAnt will open the app settings so you can review them.',
      );
      await openAppSettings();
      return;
    }

    if (!grantedNow) {
      await _showInfoDialog(
        'SpendAnt alert notifications were not enabled on this device.',
      );
    }

    await _refreshNotificationPermissionStatus();
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
    switch (_currentStepType) {
      case PermissionsIntroStep.welcome:
        await _advanceOrCompleteFlow();
        return;
      case PermissionsIntroStep.calendar:
        await _handleCalendarImport();
        if (!mounted) {
          return;
        }
        await _advanceOrCompleteFlow();
        return;
      case PermissionsIntroStep.notifications:
        await _handleNotificationAccess();
        return;
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
    await _advanceOrCompleteFlow();
  }

  Future<void> _handleNotificationAccess() async {
    await _requestPostingPermission();
    if (!mounted) {
      return;
    }

    if (kIsWeb) {
      await _advanceOrCompleteFlow();
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      await _showInfoDialog(
        'Automatic notification-based import is only available on Android.',
      );
      await _advanceOrCompleteFlow();
      return;
    }

    final hasReaderAccess = await NotificationReaderService.isAccessEnabled();
    if (!mounted) {
      return;
    }

    if (hasReaderAccess) {
      await _refreshNotificationPermissionStatus();
      await _showInfoDialog(
        'SpendAnt can already read supported Google Pay, Gmail, and Nequi notifications on this device.',
      );
      await _advanceOrCompleteFlow();
      return;
    }

    await _showInfoDialog(
      'Android also needs notification reading access to import supported purchases from Google Pay, Gmail, and Nequi. Enable it in the next screen.',
    );
    setState(() {
      _waitingForNotificationReaderAccess = true;
    });

    try {
      final opened = await NotificationReaderService.openAccessSettings();
      if (!mounted) {
        return;
      }
      if (!opened) {
        setState(() {
          _waitingForNotificationReaderAccess = false;
        });
        await _showInfoDialog(
          'Android could not open the notification reader settings on this device.',
        );
      }
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
      await _advanceOrCompleteFlow();
    }
  }

  Future<void> _advanceOrCompleteFlow() async {
    final nextStepIndex = _stepIndex + 1;
    if (nextStepIndex < _visibleSteps.length) {
      setState(() {
        _stepIndex = nextStepIndex;
      });
      return;
    }

    await _completeFlow();
  }

  Future<void> _completeFlow() async {
    if (_flowArgs.showLocationStepAfterFlow) {
      await _openLocationPermissionIntro();
      return;
    }

    await AuthMemoryStore.markLocationPermissionPromptCompleted();
    final redirect = _flowArgs.redirect;
    if (redirect != null) {
      await AppNavigationService.openRedirect(redirect);
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  PostAuthNavigationArgs? get _postAuthNavigationArgs {
    final redirect = _flowArgs.redirect;
    if (redirect == null) {
      return null;
    }

    return PostAuthNavigationArgs(redirect: redirect);
  }

  Widget _buildNotificationStatusCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.ink.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current notification status',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
          const SizedBox(height: 12),
          _buildStatusRow(
            label: 'SpendAnt alerts',
            isEnabled: _postingPermissionEnabled,
          ),
          const SizedBox(height: 10),
          _buildStatusRow(
            label: 'Read supported phone notifications',
            isEnabled: _notificationReaderEnabled,
            unsupportedLabel: 'Android only',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow({
    required String label,
    required bool? isEnabled,
    String? unsupportedLabel,
  }) {
    final statusLabel = unsupportedLabel != null && !NotificationReaderService.isSupportedPlatform
        ? unsupportedLabel
        : isEnabled == null
        ? 'Checking...'
        : isEnabled
        ? 'Enabled'
        : 'Not enabled';
    final statusColor = unsupportedLabel != null &&
            !NotificationReaderService.isSupportedPlatform
        ? AppPalette.ink.withValues(alpha: 0.68)
        : isEnabled == null
        ? AppPalette.ink.withValues(alpha: 0.68)
        : isEnabled
        ? const Color(0xFF159447)
        : const Color(0xFFB25025);

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppPalette.ink,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          statusLabel,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            color: statusColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_didResolveFlow || _visibleSteps.isEmpty) {
      return const GreenScreenScaffold(child: SizedBox.shrink());
    }

    final step = _steps[_currentStepType]!;

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
              if (_currentStepType == PermissionsIntroStep.notifications)
                _buildNotificationStatusCard(),
              BlackPrimaryButton(
                label: step.primaryLabel,
                width: step.buttonWidth,
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
    required this.buttonWidth,
    this.secondaryLabel,
  });

  final String antAssetPath;
  final String message;
  final String primaryLabel;
  final double buttonWidth;
  final String? secondaryLabel;
}
