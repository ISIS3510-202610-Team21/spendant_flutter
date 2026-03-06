import 'package:flutter_test/flutter_test.dart';

import 'package:spendant/app.dart';

void main() {
  testWidgets('renders onboarding auth entry screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SpendAntApp());

    expect(find.text('SpendAnt'), findsOneWidget);
    expect(find.text('Hi Bob.'), findsOneWidget);
    expect(find.text('Login with FingerPrint'), findsOneWidget);
    expect(find.text('Login with other User'), findsOneWidget);
  });
}
