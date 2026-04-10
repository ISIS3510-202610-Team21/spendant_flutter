import 'package:intl/intl.dart';

abstract final class AppDateFormatService {
  static final DateFormat _longMonthFormat = DateFormat('MMMM', 'en_US');
  static final DateFormat _timeFormat = DateFormat('HH:mm', 'en_US');

  static String longDate(DateTime date) {
    final month = _longMonthFormat.format(date);
    final day = date.day;
    return '$month $day${_ordinalSuffix(day)}, ${date.year}';
  }

  static String longDateWithTime(DateTime date) {
    return '${longDate(date)}, ${_timeFormat.format(date)}';
  }

  static String _ordinalSuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }

    return switch (day % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}
