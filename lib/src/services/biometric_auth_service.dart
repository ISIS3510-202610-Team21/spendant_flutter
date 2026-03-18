import 'package:local_auth/local_auth.dart';

class BiometricAvailability {
  const BiometricAvailability({
    required this.canCheckBiometrics,
    required this.isDeviceSupported,
    required this.enrolledBiometrics,
  });

  final bool canCheckBiometrics;
  final bool isDeviceSupported;
  final List<BiometricType> enrolledBiometrics;

  bool get hasEnrolledBiometrics => enrolledBiometrics.isNotEmpty;

  bool get supportsFace =>
      enrolledBiometrics.contains(BiometricType.face);

  bool get supportsFingerprint =>
      enrolledBiometrics.contains(BiometricType.fingerprint);

  bool get supportsFingerprintLogin =>
      supportsFingerprint || (hasEnrolledBiometrics && !supportsFace);
}

class BiometricAuthResult {
  const BiometricAuthResult({required this.didAuthenticate, this.message});

  final bool didAuthenticate;
  final String? message;
}

class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  Future<BiometricAvailability> getAvailability() async {
    final canCheckBiometrics = await _localAuthentication.canCheckBiometrics;
    final isDeviceSupported = await _localAuthentication.isDeviceSupported();

    List<BiometricType> enrolledBiometrics = const <BiometricType>[];
    if (canCheckBiometrics) {
      enrolledBiometrics = await _localAuthentication.getAvailableBiometrics();
    }

    return BiometricAvailability(
      canCheckBiometrics: canCheckBiometrics,
      isDeviceSupported: isDeviceSupported,
      enrolledBiometrics: enrolledBiometrics,
    );
  }

  Future<BiometricAuthResult> authenticate({
    required BiometricAvailability availability,
  }) async {
    try {
      final didAuthenticate = await _localAuthentication.authenticate(
        localizedReason: _buildPromptReason(availability),
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        return const BiometricAuthResult(didAuthenticate: true);
      }

      return const BiometricAuthResult(
        didAuthenticate: false,
        message: 'Biometric authentication was canceled or did not match.',
      );
    } on LocalAuthException catch (error) {
      return BiometricAuthResult(
        didAuthenticate: false,
        message: _messageForException(error, availability),
      );
    }
  }

  String _buildPromptReason(BiometricAvailability availability) {
    if (availability.supportsFingerprintLogin) {
      return 'Use your fingerprint to log in to SpendAnt.';
    }
    return 'Use your fingerprint to log in to SpendAnt.';
  }

  String _messageForException(
    LocalAuthException error,
    BiometricAvailability availability,
  ) {
    switch (error.code) {
      case LocalAuthExceptionCode.noBiometricHardware:
        return 'This device does not support fingerprint authentication.';
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return 'No fingerprint is configured on this device yet.';
      case LocalAuthExceptionCode.noCredentialsSet:
        return 'Set a screen lock on this device before using fingerprint authentication.';
      case LocalAuthExceptionCode.biometricLockout:
      case LocalAuthExceptionCode.temporaryLockout:
        return 'Fingerprint authentication is temporarily locked. Unlock the device and try again.';
      default:
        return 'Fingerprint authentication is not available right now.';
    }
  }
}
