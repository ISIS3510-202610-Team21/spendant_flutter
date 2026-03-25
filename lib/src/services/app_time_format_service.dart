abstract final class AppTimeFormatService {
  static final RegExp _timePattern = RegExp(
    r'^(\d{1,2}):(\d{2})(?:\s*([AaPp][Mm]))?$',
  );

  static ({int hour, int minute})? tryParseHourMinute(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final match = _timePattern.firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final parsedHour = int.tryParse(match.group(1)!);
    final parsedMinute = int.tryParse(match.group(2)!);
    final meridiem = match.group(3)?.toUpperCase();
    if (parsedHour == null || parsedMinute == null || parsedMinute > 59) {
      return null;
    }

    if (meridiem != null) {
      if (parsedHour < 1 || parsedHour > 12) {
        return null;
      }

      var normalizedHour = parsedHour % 12;
      if (meridiem == 'PM') {
        normalizedHour += 12;
      }
      return (hour: normalizedHour, minute: parsedMinute);
    }

    if (parsedHour < 0 || parsedHour > 23) {
      return null;
    }

    return (hour: parsedHour, minute: parsedMinute);
  }

  static ({int hour, int minute}) parseHourMinute(
    String rawValue, {
    int fallbackHour = 0,
    int fallbackMinute = 0,
  }) {
    return tryParseHourMinute(rawValue) ??
        (hour: fallbackHour, minute: fallbackMinute);
  }

  static String to24HourString(String rawValue, {String fallback = '00:00'}) {
    final parsed = tryParseHourMinute(rawValue);
    if (parsed == null) {
      return fallback;
    }

    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
