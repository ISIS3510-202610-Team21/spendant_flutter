import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendant/app.dart';
import 'package:spendant/src/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getTemporaryDirectory':
            case 'getApplicationSupportDirectory':
            case 'getDownloadsDirectory':
              return Directory.systemTemp.path;
            case 'getExternalStorageDirectories':
            case 'getExternalCacheDirectories':
              return <String>[Directory.systemTemp.path];
          }

          return Directory.systemTemp.path;
        });
    await LocalStorageService.init();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService().clearAllData();
  });

  testWidgets('renders onboarding auth entry screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpendAntApp());
    await tester.pumpAndSettle();

    expect(find.text('SpendAnt'), findsOneWidget);
    expect(find.text('Welcome to SpendAnt.'), findsOneWidget);
    expect(find.text('Login with FingerPrint'), findsOneWidget);
    expect(find.text('Login with other User'), findsOneWidget);
  });
}
