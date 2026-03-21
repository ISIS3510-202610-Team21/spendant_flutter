import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/expense_model.dart';
import 'calendar_availability_service.dart';
import 'habit_fixer_service.dart';
import 'spending_advice_service.dart';

typedef HabitFixerPositionLoader = Future<Position?> Function();

class HabitFixerMonitorService {
  static const Duration _recentPositionMaxAge = Duration(minutes: 10);

  HabitFixerMonitorService({
    CalendarAvailabilityService? calendarAvailabilityService,
    HabitFixerPositionLoader? positionLoader,
  }) : _calendarAvailabilityService =
           calendarAvailabilityService ?? CalendarAvailabilityService.instance,
       _positionLoader = positionLoader ?? _loadCurrentPosition;

  static final HabitFixerMonitorService instance = HabitFixerMonitorService();

  final CalendarAvailabilityService _calendarAvailabilityService;
  final HabitFixerPositionLoader _positionLoader;

  Future<SpendingAdvice?> buildTriggeredAdvice({
    required Iterable<ExpenseModel> expenses,
    DateTime? now,
  }) async {
    final referenceNow = now ?? DateTime.now();
    final position = await _positionLoader();
    if (position == null) {
      return null;
    }

    final availability = await _calendarAvailabilityService.snapshotForMoment(
      referenceNow,
    );
    if (!availability.isUserAvailable) {
      return null;
    }

    return HabitFixerService.buildTriggeredAdvice(
      expenses: expenses,
      now: referenceNow,
      currentLatitude: position.latitude,
      currentLongitude: position.longitude,
      isCalendarAvailable: true,
    );
  }

  static Future<Position?> _loadCurrentPosition() async {
    try {
      if (kIsWeb) {
        return null;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final lastKnownPosition = await Geolocator.getLastKnownPosition();
      if (lastKnownPosition != null &&
          DateTime.now().difference(lastKnownPosition.timestamp) <=
              _recentPositionMaxAge) {
        return lastKnownPosition;
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (error) {
      debugPrint('HabitFixerMonitorService position lookup failed: $error');
      return null;
    }
  }
}
