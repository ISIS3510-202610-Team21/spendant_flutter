import 'package:flutter/widgets.dart';

import '../services/connectivity_monitor.dart';

/// Adds real-time connectivity awareness to any [State] without coupling the
/// widget directly to the network service.
///
/// Wire it in by:
/// 1. Adding `with ConnectivityAwareStateMixin<YourWidget>` to the state.
/// 2. Implementing [onConnectivityChanged].
///
/// The mixin registers the listener in [initState] and removes it in [dispose]
/// automatically — no manual setup needed.
///
/// ```dart
/// class _MapScreenState extends State<MapScreen>
///     with ConnectivityAwareStateMixin<MapScreen> {
///
///   bool _isOffline = false;
///
///   @override
///   void onConnectivityChanged({required bool isOnline}) {
///     setState(() => _isOffline = !isOnline);
///   }
/// }
/// ```
mixin ConnectivityAwareStateMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ConnectivityMonitor.isOnlineListenable
        .addListener(_dispatchConnectivityChange);
  }

  @override
  void dispose() {
    ConnectivityMonitor.isOnlineListenable
        .removeListener(_dispatchConnectivityChange);
    super.dispose();
  }

  /// Current connectivity state, readable without a BuildContext.
  bool get isConnected => ConnectivityMonitor.isOnline;

  void _dispatchConnectivityChange() {
    if (!mounted) return;
    onConnectivityChanged(isOnline: ConnectivityMonitor.isOnline);
  }

  /// Called on the main isolate whenever connectivity changes.
  ///
  /// [isOnline] is `true` when the connection is restored, `false` when lost.
  /// Always called while [mounted] is true.
  void onConnectivityChanged({required bool isOnline});
}
