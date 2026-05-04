import 'dart:async';

import 'package:flutter/material.dart';
import '../services/connectivity_monitor.dart';
import '../theme/spendant_theme.dart';

/// A non-intrusive animated banner that reacts to real-time connectivity changes.
///
/// Shows an amber banner when the device is offline. [offlineMessage] explains
/// what happened; the optional [impact] line explains the functional consequence
/// (e.g. "Map quality may be degraded.").
///
/// When connectivity is restored a green "Connection restored" banner appears
/// briefly ([restoredVisibleDuration]) and then disappears.
///
/// The banner never blocks the UI — it sits inline in the widget tree and
/// animates its height smoothly via [AnimatedSize].
///
/// Usage:
/// ```dart
/// ConnectivityStatusBanner(
///   offlineMessage: 'You lost internet connection.',
///   impact: 'Map quality may be degraded.',
/// )
/// ```
class ConnectivityStatusBanner extends StatefulWidget {
  const ConnectivityStatusBanner({
    super.key,
    required this.offlineMessage,
    this.impact,
    this.restoredMessage = 'Connection restored',
    this.restoredVisibleDuration = const Duration(seconds: 3),
  });

  final String offlineMessage;

  /// Optional second line describing what functionality is affected.
  final String? impact;

  final String restoredMessage;
  final Duration restoredVisibleDuration;

  @override
  State<ConnectivityStatusBanner> createState() =>
      _ConnectivityStatusBannerState();
}

class _ConnectivityStatusBannerState extends State<ConnectivityStatusBanner> {
  // Seed from current state so the banner is correct immediately on first build.
  bool _isOnline = ConnectivityMonitor.isOnline;
  bool _showingRestored = false;
  Timer? _restoredTimer;

  @override
  void initState() {
    super.initState();
    ConnectivityMonitor.isOnlineListenable
        .addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityMonitor.isOnlineListenable
        .removeListener(_onConnectivityChanged);
    _restoredTimer?.cancel();
    super.dispose();
  }

  void _onConnectivityChanged() {
    final nowOnline = ConnectivityMonitor.isOnline;

    if (nowOnline && !_isOnline) {
      // offline → online: show the "restored" banner transiently.
      _restoredTimer?.cancel();
      setState(() {
        _isOnline = true;
        _showingRestored = true;
      });
      _restoredTimer = Timer(widget.restoredVisibleDuration, () {
        if (mounted) setState(() => _showingRestored = false);
      });
    } else if (!nowOnline && _isOnline) {
      // online → offline: immediately swap to the offline banner.
      _restoredTimer?.cancel();
      setState(() {
        _isOnline = false;
        _showingRestored = false;
      });
    }
  }

  bool get _shouldShow => !_isOnline || _showingRestored;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: _shouldShow
          ? (_showingRestored
              ? _RestoredBanner(message: widget.restoredMessage)
              : _OfflineBanner(
                  message: widget.offlineMessage,
                  impact: widget.impact,
                ))
          : const SizedBox.shrink(),
    );
  }
}

// ─── Internal banner widgets ───────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message, this.impact});

  final String message;
  final String? impact;

  @override
  Widget build(BuildContext context) {
    final text = (impact != null && impact!.trim().isNotEmpty)
        ? '$message $impact'
        : message;

    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

class _RestoredBanner extends StatelessWidget {
  const _RestoredBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppPalette.green,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
