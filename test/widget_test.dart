import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendant/app.dart';

void main() {
  testWidgets('renders onboarding auth entry screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SpendAntApp());
    await tester.pumpAndSettle();

    expect(find.text('SpendAnt'), findsOneWidget);
    expect(find.text('Welcome to SpendAnt.'), findsOneWidget);
    expect(find.text('Login with FingerPrint'), findsOneWidget);
    expect(find.text('Login with other User'), findsOneWidget);
  });
}
