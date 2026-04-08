import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendant/src/services/auth_memory_store.dart';

void main() {
  group('AuthMemoryStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('shows permissions onboarding for a different user', () async {
      await AuthMemoryStore.initialize();
      await AuthMemoryStore.saveSession(
        userId: 7,
        username: 'alice',
        rememberLogin: false,
        fingerprintEnabled: false,
      );
      await AuthMemoryStore.markLocationPermissionPromptCompleted();
      await AuthMemoryStore.clearSession();

      await AuthMemoryStore.saveSession(
        userId: 8,
        username: 'bob',
        rememberLogin: false,
        fingerprintEnabled: false,
      );

      final state = await AuthMemoryStore.loadGreetingState();
      expect(state.userId, 8);
      expect(state.needsLocationPermissionPrompt, isTrue);
    });

    test('keeps permissions onboarding completed for the same user', () async {
      await AuthMemoryStore.initialize();
      await AuthMemoryStore.saveSession(
        userId: 7,
        username: 'alice',
        rememberLogin: false,
        fingerprintEnabled: false,
      );
      await AuthMemoryStore.markLocationPermissionPromptCompleted();
      await AuthMemoryStore.clearSession();

      await AuthMemoryStore.saveSession(
        userId: 7,
        username: 'alice',
        rememberLogin: false,
        fingerprintEnabled: false,
      );

      final state = await AuthMemoryStore.loadGreetingState();
      expect(state.userId, 7);
      expect(state.needsLocationPermissionPrompt, isFalse);
    });
  });
}
