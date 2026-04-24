import 'package:flutter/material.dart';

import '../services/connectivity_monitor.dart';

/// A slim black banner with white text shown whenever the device is offline.
/// Animates in/out smoothly using [AnimatedSize] + [AnimatedOpacity].
class NoInternetBanner extends StatelessWidget {
  const NoInternetBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityMonitor.isOnlineListenable,
      builder: (context, isOnline, _) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: isOnline
              ? const SizedBox.shrink()
              : _BannerContent(),
        );
      },
    );
  }
}

class _BannerContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Text(
        'There is no internet connection available!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
