import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import 'spending_advice_service.dart';

class RegretHotspot {
  const RegretHotspot({
    required this.clusterId,
    required this.latitude,
    required this.longitude,
    required this.locationLabel,
    required this.medianMinutesOfDay,
    required this.memberCount,
    required this.averageAmount,
    required this.category,
  });

  final String clusterId;
  final double latitude;
  final double longitude;
  final String locationLabel;
  final int medianMinutesOfDay;
  final int memberCount;
  final double averageAmount;
  final String? category;
}

abstract final class HabitFixerService {
  static const double hotspotRadiusMeters = 200;
  static const int hotspotTimeWindowMinutes = 90;
  static final DateFormat _timeFormat = DateFormat('HH:mm');

  static SpendingAdvice? buildTriggeredAdvice({
    required Iterable<ExpenseModel> expenses,
    required DateTime now,
    required double currentLatitude,
    required double currentLongitude,
    required bool isCalendarAvailable,
  }) {
    if (!isCalendarAvailable) {
      return null;
    }

    final hotspots = findHotspots(expenses);
    if (hotspots.isEmpty) {
      return null;
    }

    final currentMinutes = now.hour * 60 + now.minute;
    RegretHotspot? bestMatch;
    var bestDistanceMeters = double.infinity;
    var bestTimeDelta = 1 << 30;

    for (final hotspot in hotspots) {
      final distanceMeters = distanceBetweenMeters(
        startLatitude: currentLatitude,
        startLongitude: currentLongitude,
        endLatitude: hotspot.latitude,
        endLongitude: hotspot.longitude,
      );
      if (distanceMeters > hotspotRadiusMeters) {
        continue;
      }

      final timeDelta = _minutesDifferenceOnClock(
        currentMinutes,
        hotspot.medianMinutesOfDay,
      );
      if (timeDelta > hotspotTimeWindowMinutes) {
        continue;
      }

      if (bestMatch == null ||
          hotspot.memberCount > bestMatch.memberCount ||
          (hotspot.memberCount == bestMatch.memberCount &&
              distanceMeters < bestDistanceMeters) ||
          (hotspot.memberCount == bestMatch.memberCount &&
              distanceMeters == bestDistanceMeters &&
              timeDelta < bestTimeDelta)) {
        bestMatch = hotspot;
        bestDistanceMeters = distanceMeters;
        bestTimeDelta = timeDelta;
      }
    }

    if (bestMatch == null) {
      return null;
    }

    final signalSuffix = _dayKey(now);
    final locationLabel = bestMatch.locationLabel;
    final timeLabel = _formatTime(bestMatch.medianMinutesOfDay);
    final title = locationLabel == 'this place'
        ? 'Pause before spending here'
        : 'Pause before spending at $locationLabel';

    return SpendingAdvice(
      signalId: 'advice:habit-fixer:${bestMatch.clusterId}:$signalSuffix',
      notificationId: 'habit-fixer-${bestMatch.clusterId}-$signalSuffix',
      kind: SpendingAdviceKind.regretHotspot,
      detectedAt: now,
      title: title,
      subtitle:
          '${bestMatch.memberCount} regretted purchases around $timeLabel',
      amount: null,
      category: bestMatch.category,
      detailTitle: 'You have a regret pattern here',
      detailMessage:
          'You previously marked ${bestMatch.memberCount} purchases near $locationLabel around $timeLabel as regretted. You are back in the same area and your calendar looks free, so take a moment before spending.',
    );
  }

  static List<RegretHotspot> findHotspots(Iterable<ExpenseModel> expenses) {
    final regrettedExpenses = expenses
        .where((expense) => expense.isRegretted)
        .where(
          (expense) => expense.latitude != null && expense.longitude != null,
        )
        .toList();
    if (regrettedExpenses.length < 2) {
      return const <RegretHotspot>[];
    }

    final hotspotsById = <String, RegretHotspot>{};
    for (final anchor in regrettedExpenses) {
      final anchorLatitude = anchor.latitude!;
      final anchorLongitude = anchor.longitude!;
      final anchorMinutes = _minutesOfDayForExpense(anchor);

      final nearbyMembers = regrettedExpenses.where((candidate) {
        final distanceMeters = distanceBetweenMeters(
          startLatitude: anchorLatitude,
          startLongitude: anchorLongitude,
          endLatitude: candidate.latitude!,
          endLongitude: candidate.longitude!,
        );
        if (distanceMeters > hotspotRadiusMeters) {
          return false;
        }

        final candidateMinutes = _minutesOfDayForExpense(candidate);
        return _minutesDifferenceOnClock(anchorMinutes, candidateMinutes) <=
            hotspotTimeWindowMinutes;
      }).toList();
      if (nearbyMembers.length < 2) {
        continue;
      }

      final centroidLatitude =
          nearbyMembers
              .map((expense) => expense.latitude!)
              .reduce((sum, value) => sum + value) /
          nearbyMembers.length;
      final centroidLongitude =
          nearbyMembers
              .map((expense) => expense.longitude!)
              .reduce((sum, value) => sum + value) /
          nearbyMembers.length;
      final normalizedMinutes =
          nearbyMembers
              .map(
                (expense) => _alignClockMinutes(
                  _minutesOfDayForExpense(expense),
                  anchorMinutes,
                ),
              )
              .toList()
            ..sort();
      final medianMinutes = _normalizeClockMinutes(
        _median(normalizedMinutes).round(),
      );

      final refinedMembers = regrettedExpenses.where((candidate) {
        final distanceMeters = distanceBetweenMeters(
          startLatitude: centroidLatitude,
          startLongitude: centroidLongitude,
          endLatitude: candidate.latitude!,
          endLongitude: candidate.longitude!,
        );
        if (distanceMeters > hotspotRadiusMeters) {
          return false;
        }

        final candidateMinutes = _minutesOfDayForExpense(candidate);
        return _minutesDifferenceOnClock(candidateMinutes, medianMinutes) <=
            hotspotTimeWindowMinutes;
      }).toList();
      if (refinedMembers.length < 2) {
        continue;
      }

      final clusterId = _clusterId(
        latitude: centroidLatitude,
        longitude: centroidLongitude,
        medianMinutesOfDay: medianMinutes,
      );
      final memberAmounts = refinedMembers.map((expense) => expense.amount);
      final averageAmount =
          memberAmounts.reduce((sum, value) => sum + value) /
          refinedMembers.length;
      final locationLabel = _mostCommonLocationLabel(refinedMembers);
      final category = _mostCommonCategory(refinedMembers);
      final hotspot = RegretHotspot(
        clusterId: clusterId,
        latitude: centroidLatitude,
        longitude: centroidLongitude,
        locationLabel: locationLabel,
        medianMinutesOfDay: medianMinutes,
        memberCount: refinedMembers.length,
        averageAmount: averageAmount,
        category: category,
      );

      final existing = hotspotsById[clusterId];
      if (existing == null ||
          hotspot.memberCount > existing.memberCount ||
          (hotspot.memberCount == existing.memberCount &&
              hotspot.averageAmount > existing.averageAmount)) {
        hotspotsById[clusterId] = hotspot;
      }
    }

    final hotspots = hotspotsById.values.toList()
      ..sort((left, right) {
        final memberComparison = right.memberCount.compareTo(left.memberCount);
        if (memberComparison != 0) {
          return memberComparison;
        }

        return right.averageAmount.compareTo(left.averageAmount);
      });
    return hotspots;
  }

  static double distanceBetweenMeters({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _degreesToRadians(endLatitude - startLatitude);
    final longitudeDelta = _degreesToRadians(endLongitude - startLongitude);
    final startLatitudeRadians = _degreesToRadians(startLatitude);
    final endLatitudeRadians = _degreesToRadians(endLatitude);
    final haversine =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(startLatitudeRadians) *
            math.cos(endLatitudeRadians) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final arc = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
    return earthRadiusMeters * arc;
  }

  static double _degreesToRadians(double value) => value * math.pi / 180;

  static int _minutesOfDayForExpense(ExpenseModel expense) {
    final parts = expense.time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return hour.clamp(0, 23) * 60 + minute.clamp(0, 59);
  }

  static int _minutesDifferenceOnClock(int left, int right) {
    final delta = (left - right).abs();
    return math.min(delta, 1440 - delta);
  }

  static int _alignClockMinutes(int value, int reference) {
    var aligned = value;
    while (aligned - reference > 720) {
      aligned -= 1440;
    }
    while (reference - aligned > 720) {
      aligned += 1440;
    }
    return aligned;
  }

  static int _normalizeClockMinutes(int value) {
    final normalized = value % 1440;
    return normalized < 0 ? normalized + 1440 : normalized;
  }

  static double _median(List<int> sortedValues) {
    if (sortedValues.isEmpty) {
      return 0;
    }

    final middleIndex = sortedValues.length ~/ 2;
    if (sortedValues.length.isOdd) {
      return sortedValues[middleIndex].toDouble();
    }

    return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2;
  }

  static String _clusterId({
    required double latitude,
    required double longitude,
    required int medianMinutesOfDay,
  }) {
    final latitudeKey = latitude.toStringAsFixed(4);
    final longitudeKey = longitude.toStringAsFixed(4);
    final timeKey = (medianMinutesOfDay / 15).round().toString();
    return '$latitudeKey:$longitudeKey:$timeKey';
  }

  static String _mostCommonLocationLabel(List<ExpenseModel> expenses) {
    final counts = <String, int>{};
    for (final expense in expenses) {
      final candidate = expense.locationName?.trim();
      if (candidate == null || candidate.isEmpty) {
        continue;
      }
      counts.update(candidate, (count) => count + 1, ifAbsent: () => 1);
    }

    if (counts.isEmpty) {
      return 'this place';
    }

    return counts.entries.reduce((left, right) {
      if (right.value > left.value) {
        return right;
      }
      return left;
    }).key;
  }

  static String? _mostCommonCategory(List<ExpenseModel> expenses) {
    final counts = <String, int>{};
    for (final expense in expenses) {
      final category = expense.primaryCategory?.trim();
      if (category == null || category.isEmpty) {
        continue;
      }
      counts.update(category, (count) => count + 1, ifAbsent: () => 1);
    }

    if (counts.isEmpty) {
      return null;
    }

    return counts.entries.reduce((left, right) {
      if (right.value > left.value) {
        return right;
      }
      return left;
    }).key;
  }

  static String _formatTime(int minutesOfDay) {
    final normalized = _normalizeClockMinutes(minutesOfDay);
    final instant = DateTime(2026, 1, 1, normalized ~/ 60, normalized % 60);
    return _timeFormat.format(instant);
  }

  static String _dayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
