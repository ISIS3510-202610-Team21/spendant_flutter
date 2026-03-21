import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firstfloor_calendar/firstfloor_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'auth_memory_store.dart';

enum CalendarConnectionStatus {
  connected,
  emptySchedule,
  notConnected,
  canceled,
  invalidFile,
  unsupported,
  error,
}

class ClassScheduleSummary {
  const ClassScheduleSummary({
    required this.fileName,
    required this.recurringEventCount,
    required this.oneTimeEventCount,
  });

  final String fileName;
  final int recurringEventCount;
  final int oneTimeEventCount;

  int get totalEventCount => recurringEventCount + oneTimeEventCount;

  bool get hasRecurringEvents => recurringEventCount > 0;
}

class CalendarBusyPeriod {
  const CalendarBusyPeriod({
    required this.summary,
    required this.start,
    required this.end,
    required this.isRecurring,
  });

  final String summary;
  final DateTime start;
  final DateTime end;
  final bool isRecurring;
}

class CalendarAccessResult {
  const CalendarAccessResult({
    required this.status,
    required this.schedule,
    this.message,
  });

  final CalendarConnectionStatus status;
  final ClassScheduleSummary? schedule;
  final String? message;

  bool get isConnected =>
      status == CalendarConnectionStatus.connected && schedule != null;
}

class CalendarAvailabilitySnapshot {
  const CalendarAvailabilitySnapshot({
    required this.status,
    required this.schedule,
    required this.isUserAvailable,
    required this.blockingPeriods,
    this.message,
  });

  final CalendarConnectionStatus status;
  final ClassScheduleSummary? schedule;
  final bool isUserAvailable;
  final List<CalendarBusyPeriod> blockingPeriods;
  final String? message;

  bool get hasSchedule =>
      status == CalendarConnectionStatus.connected && schedule != null;
}

class CalendarAvailabilityService {
  CalendarAvailabilityService({
    Future<SharedPreferences> Function()? preferencesLoader,
    void Function()? timezoneInitializer,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _timezoneInitializer = timezoneInitializer ?? tz.initializeTimeZones;

  static final CalendarAvailabilityService instance =
      CalendarAvailabilityService();

  static const int _studentWindowStartMinutes = 6 * 60 + 30;
  static const int _studentWindowEndMinutes = 21 * 60;
  static const Duration _occurrenceSearchLookBehind = Duration(hours: 12);
  static const String _rawIcsKeyPrefix = 'class_schedule_ics_v1';
  static const String _fileNameKeyPrefix = 'class_schedule_file_name_v1';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final void Function() _timezoneInitializer;

  bool _didInitialize = false;
  Future<void>? _initializing;
  int? _cachedUserId;
  String? _cachedRawIcs;
  _ImportedSchedule? _cachedSchedule;

  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }

    final runningInitialization = _initializing;
    if (runningInitialization != null) {
      await runningInitialization;
      return;
    }

    final initialization = Future<void>(() {
      _timezoneInitializer();
    });
    _initializing = initialization;

    try {
      await initialization;
      _didInitialize = true;
    } finally {
      if (identical(_initializing, initialization)) {
        _initializing = null;
      }
    }
  }

  Future<CalendarAccessResult> importSchedule() async {
    await initialize();

    FilePickerResult? pickedFile;
    try {
      pickedFile = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const <String>['ics'],
      );
    } on MissingPluginException {
      return const CalendarAccessResult(
        status: CalendarConnectionStatus.unsupported,
        schedule: null,
        message:
            'This device cannot open the .ics file picker on the current build.',
      );
    } catch (error) {
      return CalendarAccessResult(
        status: CalendarConnectionStatus.error,
        schedule: null,
        message: 'The class schedule picker failed: $error',
      );
    }

    if (pickedFile == null || pickedFile.files.isEmpty) {
      return const CalendarAccessResult(
        status: CalendarConnectionStatus.canceled,
        schedule: null,
        message: 'Class schedule import was canceled.',
      );
    }

    final selectedFile = pickedFile.files.single;
    final bytes = selectedFile.bytes;
    if (bytes == null) {
      return const CalendarAccessResult(
        status: CalendarConnectionStatus.error,
        schedule: null,
        message: 'The selected .ics file could not be opened.',
      );
    }

    return importScheduleFromFile(
      fileName: selectedFile.name,
      rawIcs: utf8.decode(bytes, allowMalformed: true),
    );
  }

  @visibleForTesting
  Future<CalendarAccessResult> importScheduleFromFile({
    required String fileName,
    required String rawIcs,
  }) async {
    await initialize();

    final parsedSchedule = _parseSchedule(
      fileName: _normalizeFileName(fileName),
      rawIcs: _normalizeRawIcs(rawIcs),
    );
    if (parsedSchedule == null) {
      return const CalendarAccessResult(
        status: CalendarConnectionStatus.invalidFile,
        schedule: null,
        message:
            'The selected file is not a valid .ics calendar or could not be parsed.',
      );
    }

    if (parsedSchedule.summary.totalEventCount == 0) {
      return CalendarAccessResult(
        status: CalendarConnectionStatus.emptySchedule,
        schedule: parsedSchedule.summary,
        message:
            'The imported .ics file does not contain timed events that can be used as a class schedule.',
      );
    }

    await _persistSchedule(parsedSchedule);
    return CalendarAccessResult(
      status: CalendarConnectionStatus.connected,
      schedule: parsedSchedule.summary,
      message: _successMessageFor(parsedSchedule.summary),
    );
  }

  Future<CalendarAvailabilitySnapshot> snapshotForMoment(
    DateTime at, {
    Duration graceBefore = const Duration(minutes: 5),
    Duration lookAhead = const Duration(minutes: 30),
  }) async {
    await initialize();

    _ImportedSchedule? schedule;
    try {
      schedule = await _loadImportedSchedule();
    } catch (error) {
      return CalendarAvailabilitySnapshot(
        status: CalendarConnectionStatus.invalidFile,
        schedule: null,
        isUserAvailable: false,
        blockingPeriods: const <CalendarBusyPeriod>[],
        message:
            'The saved .ics schedule could not be read anymore. Import it again. Technical detail: $error',
      );
    }

    if (schedule == null) {
      return const CalendarAvailabilitySnapshot(
        status: CalendarConnectionStatus.notConnected,
        schedule: null,
        isUserAvailable: false,
        blockingPeriods: <CalendarBusyPeriod>[],
        message:
            'Import a class schedule .ics file to enable free-time checks for habit warnings.',
      );
    }

    if (!_isWithinStudentHours(at)) {
      return CalendarAvailabilitySnapshot(
        status: CalendarConnectionStatus.connected,
        schedule: schedule.summary,
        isUserAvailable: false,
        blockingPeriods: const <CalendarBusyPeriod>[],
        message:
            'Habit warnings are limited to the student schedule window from 06:30 to 21:00.',
      );
    }

    final blockingPeriods = _collectRecurringBlockingPeriods(
      schedule.calendar,
      at: at,
      graceBefore: graceBefore,
      lookAhead: lookAhead,
    )..sort((left, right) => left.start.compareTo(right.start));

    return CalendarAvailabilitySnapshot(
      status: CalendarConnectionStatus.connected,
      schedule: schedule.summary,
      isUserAvailable: blockingPeriods.isEmpty,
      blockingPeriods: blockingPeriods,
      message: blockingPeriods.isEmpty
          ? null
          : 'A recurring class already overlaps this time window.',
    );
  }

  Future<void> clearImportedSchedule() async {
    final prefs = await _preferencesLoader();
    await prefs.remove(_rawIcsKey);
    await prefs.remove(_fileNameKey);

    if (_cachedUserId == _currentUserId) {
      _cachedRawIcs = null;
      _cachedSchedule = null;
    }
  }

  List<CalendarBusyPeriod> _collectRecurringBlockingPeriods(
    Calendar calendar, {
    required DateTime at,
    required Duration graceBefore,
    required Duration lookAhead,
  }) {
    final windowStart = at.subtract(graceBefore);
    final windowEnd = at.add(lookAhead);
    final searchStart = windowStart.subtract(_occurrenceSearchLookBehind);
    final queryStart = _toCalDateTime(searchStart);
    final queryEnd = _toCalDateTime(windowEnd);
    final blockingPeriods = <CalendarBusyPeriod>[];

    for (final event in calendar.events) {
      if (!_shouldTrackEvent(event) || !event.isRecurring) {
        continue;
      }

      for (final occurrence in event.occurrences(
        start: queryStart,
        end: queryEnd,
      )) {
        final start = occurrence.native.toLocal();
        final end = _occurrenceEndFor(event, occurrence).toLocal();
        if (!_overlaps(
          periodStart: start,
          periodEnd: end,
          windowStart: windowStart,
          windowEnd: windowEnd,
        )) {
          continue;
        }

        blockingPeriods.add(
          CalendarBusyPeriod(
            summary: _eventSummary(event),
            start: start,
            end: end,
            isRecurring: true,
          ),
        );
      }
    }

    return blockingPeriods;
  }

  Future<void> _persistSchedule(_ImportedSchedule schedule) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(_rawIcsKey, schedule.rawIcs);
    await prefs.setString(_fileNameKey, schedule.summary.fileName);

    _cachedUserId = _currentUserId;
    _cachedRawIcs = schedule.rawIcs;
    _cachedSchedule = schedule;
  }

  Future<_ImportedSchedule?> _loadImportedSchedule() async {
    final prefs = await _preferencesLoader();
    final rawIcs = prefs.getString(_rawIcsKey)?.trim();
    if (rawIcs == null || rawIcs.isEmpty) {
      return null;
    }

    if (_cachedUserId == _currentUserId &&
        _cachedRawIcs == rawIcs &&
        _cachedSchedule != null) {
      return _cachedSchedule;
    }

    final fileName = _normalizeFileName(prefs.getString(_fileNameKey));
    final schedule = _parseSchedule(fileName: fileName, rawIcs: rawIcs);
    if (schedule == null) {
      throw StateError('Stored .ics data is no longer valid.');
    }

    _cachedUserId = _currentUserId;
    _cachedRawIcs = rawIcs;
    _cachedSchedule = schedule;
    return schedule;
  }

  _ImportedSchedule? _parseSchedule({
    required String fileName,
    required String rawIcs,
  }) {
    try {
      final calendar = CalendarParser().parseFromString(rawIcs);
      final timedEvents = calendar.events.where(_shouldTrackEvent).toList();
      final recurringEventCount = timedEvents.where((event) {
        return event.isRecurring;
      }).length;
      final oneTimeEventCount = timedEvents.length - recurringEventCount;

      return _ImportedSchedule(
        rawIcs: rawIcs,
        calendar: calendar,
        summary: ClassScheduleSummary(
          fileName: fileName,
          recurringEventCount: recurringEventCount,
          oneTimeEventCount: oneTimeEventCount,
        ),
      );
    } catch (error) {
      debugPrint('CalendarAvailabilityService failed to parse .ics: $error');
      return null;
    }
  }

  bool _shouldTrackEvent(EventComponent event) {
    return event.dtstart != null && !event.isAllDay;
  }

  DateTime _occurrenceEndFor(EventComponent event, CalDateTime occurrence) {
    final duration = event.effectiveDuration;
    if (duration != null) {
      return occurrence.addDuration(duration).native;
    }

    return occurrence.native;
  }

  bool _isWithinStudentHours(DateTime at) {
    final minutesOfDay = at.hour * 60 + at.minute;
    return minutesOfDay >= _studentWindowStartMinutes &&
        minutesOfDay <= _studentWindowEndMinutes;
  }

  bool _overlaps({
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return periodStart.isBefore(windowEnd) && periodEnd.isAfter(windowStart);
  }

  String _eventSummary(EventComponent event) {
    final summary = event.summary?.trim();
    if (summary == null || summary.isEmpty) {
      return 'Class block';
    }
    return summary;
  }

  CalDateTime _toCalDateTime(DateTime value) {
    final localValue = value.toLocal();
    return CalDateTime.local(
      localValue.year,
      localValue.month,
      localValue.day,
      localValue.hour,
      localValue.minute,
      localValue.second,
    );
  }

  String _normalizeRawIcs(String rawIcs) {
    return rawIcs.replaceFirst('\uFEFF', '').trim();
  }

  String _normalizeFileName(String? fileName) {
    final normalized = fileName?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'class-schedule.ics';
    }
    return normalized;
  }

  String? _successMessageFor(ClassScheduleSummary summary) {
    if (!summary.hasRecurringEvents) {
      return 'The .ics file was imported, but no recurring classes were found. SpendAnt will only block habit warnings with recurring schedule events between 06:30 and 21:00.';
    }

    if (summary.oneTimeEventCount == 0) {
      return 'Recurring classes will block habit warnings between 06:30 and 21:00.';
    }

    return 'Recurring classes will block habit warnings between 06:30 and 21:00. One-time events are kept as context only, so they do not block the habit fixer by themselves.';
  }

  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  String get _rawIcsKey => '$_rawIcsKeyPrefix-$_currentUserId';

  String get _fileNameKey => '$_fileNameKeyPrefix-$_currentUserId';
}

class _ImportedSchedule {
  const _ImportedSchedule({
    required this.rawIcs,
    required this.calendar,
    required this.summary,
  });

  final String rawIcs;
  final Calendar calendar;
  final ClassScheduleSummary summary;
}
