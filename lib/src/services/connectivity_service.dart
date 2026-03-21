import 'package:connectivity_plus/connectivity_plus.dart';

abstract interface class ConnectivityService {
  Future<bool> hasInternetConnection();
}

class DefaultConnectivityService implements ConnectivityService {
  DefaultConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> hasInternetConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((value) => value != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
