import 'package:flutter_test/flutter_test.dart';
import 'package:spendant/src/services/google_pay_notification_parser.dart';
import 'package:spendant/src/services/notification_reader_service.dart';

void main() {
  group('GooglePayNotificationParser', () {
    test('parses a grocery purchase from Google Wallet', () {
      const event = NotificationReaderEvent(
        eventId: 'wallet-1',
        packageName: 'com.google.android.apps.walletnfcrel',
        appName: 'Google Wallet',
        title: 'Payment successful',
        text: 'You paid COP 18,500 at Exito',
        bigText: 'You paid COP 18,500 at Exito with your saved card.',
        subText: '',
        postedAtMillis: 1710808200000,
      );

      final parsed = GooglePayNotificationParser.parse(event);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Exito');
      expect(parsed.amount, 18500);
      expect(parsed.primaryCategory, 'Food');
      expect(parsed.detailLabels, <String>['Groceries']);
    });

    test('parses a food delivery purchase from Google Pay', () {
      const event = NotificationReaderEvent(
        eventId: 'wallet-2',
        packageName: 'com.google.android.apps.nbu.paisa.user',
        appName: 'Google Pay',
        title: 'Pago realizado',
        text: r'Pagaste $24.900 en Uber Eats',
        bigText: '',
        subText: '',
        postedAtMillis: 1710808200000,
      );

      final parsed = GooglePayNotificationParser.parse(event);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Uber Eats');
      expect(parsed.amount, 24900);
      expect(parsed.primaryCategory, 'Food');
      expect(parsed.detailLabels, <String>['Food Delivery']);
    });

    test('ignores refund notifications', () {
      const event = NotificationReaderEvent(
        eventId: 'wallet-3',
        packageName: 'com.google.android.apps.walletnfcrel',
        appName: 'Google Wallet',
        title: 'Refund issued',
        text: 'Refund of COP 10,000 from Uber',
        bigText: '',
        subText: '',
        postedAtMillis: 1710808200000,
      );

      final parsed = GooglePayNotificationParser.parse(event);

      expect(parsed, isNull);
    });
  });
}
