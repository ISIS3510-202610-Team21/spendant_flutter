import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendant/src/services/calendar_availability_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarAvailabilityService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'imports an .ics schedule and only recurring classes block availability',
      () async {
        final service = CalendarAvailabilityService(timezoneInitializer: () {});

        final importResult = await service.importScheduleFromFile(
          fileName: 'semester.ics',
          rawIcs: _sampleClassCalendar,
        );

        expect(importResult.status, CalendarConnectionStatus.connected);
        expect(importResult.schedule, isNotNull);
        expect(importResult.schedule!.recurringEventCount, 1);
        expect(importResult.schedule!.oneTimeEventCount, 1);

        final recurringSnapshot = await service.snapshotForMoment(
          DateTime(2026, 3, 23, 8, 15),
        );
        expect(recurringSnapshot.status, CalendarConnectionStatus.connected);
        expect(recurringSnapshot.isUserAvailable, isFalse);
        expect(recurringSnapshot.blockingPeriods, hasLength(1));
        expect(recurringSnapshot.blockingPeriods.first.summary, 'Algorithms');

        final oneTimeSnapshot = await service.snapshotForMoment(
          DateTime(2026, 3, 20, 10, 15),
        );
        expect(oneTimeSnapshot.status, CalendarConnectionStatus.connected);
        expect(oneTimeSnapshot.isUserAvailable, isTrue);
        expect(oneTimeSnapshot.blockingPeriods, isEmpty);
      },
    );

    test(
      'habit warnings stay off outside the student schedule window',
      () async {
        final service = CalendarAvailabilityService(timezoneInitializer: () {});

        await service.importScheduleFromFile(
          fileName: 'semester.ics',
          rawIcs: _sampleClassCalendar,
        );

        final lateSnapshot = await service.snapshotForMoment(
          DateTime(2026, 3, 23, 21, 15),
        );

        expect(lateSnapshot.status, CalendarConnectionStatus.connected);
        expect(lateSnapshot.isUserAvailable, isFalse);
        expect(lateSnapshot.blockingPeriods, isEmpty);
        expect(lateSnapshot.message, contains('06:30 to 21:00'));
      },
    );
  });
}

const String _sampleClassCalendar = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//SpendAnt Tests//EN
BEGIN:VEVENT
UID:algorithms@example.com
DTSTAMP:20260320T000000Z
DTSTART:20260316T080000
DTEND:20260316T093000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE
SUMMARY:Algorithms
END:VEVENT
BEGIN:VEVENT
UID:guest-talk@example.com
DTSTAMP:20260320T000000Z
DTSTART:20260320T100000
DTEND:20260320T110000
SUMMARY:Guest Talk
END:VEVENT
END:VCALENDAR
''';
