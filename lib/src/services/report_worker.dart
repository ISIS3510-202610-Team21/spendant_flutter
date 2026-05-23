import 'dart:isolate';

import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import '../models/financial_report.dart';
import '../services/auth_memory_store.dart';
import '../services/currency_provider.dart';
import '../services/local_storage_service.dart';
import '../services/report_cache_service.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

abstract final class ReportWorker {
  /// Builds a [FinancialReport] for the given [startDate]–[endDate] range,
  /// serving from cache when fresh (< 24 h).
  ///
  /// 1. Check 24-h cache → instant return on hit.
  /// 2. Read expenses from Hive on main thread (platform channel needed).
  /// 3. Aggregate in [Isolate.run] — UI never blocks.
  /// 4. Increment usage counter, persist to cache, return.
  static Future<FinancialReport?> generate({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final userId = AuthMemoryStore.currentUserIdOrGuest;
    final start = DateUtils.dateOnly(startDate);
    final end   = DateUtils.dateOnly(endDate);

    // ── Cache hit → serve instantly ───────────────────────────────────────
    final cached = await ReportCacheService.get(userId, start, end);
    if (cached != null) return cached;

    // ── Collect raw data on main thread ───────────────────────────────────
    final allExpenses = LocalStorageService.expenseBox.values
        .where((e) => e.userId == userId)
        .where((e) {
          final d = DateUtils.dateOnly(e.date);
          return !d.isBefore(start) && !d.isAfter(end);
        })
        .toList(growable: false);

    final usageCount = await ReportCacheService.getUsageCount(userId) + 1;
    await ReportCacheService.incrementUsageCount(userId);

    final periodLabel = _buildLabel(start, end);

    if (allExpenses.isEmpty) {
      final empty = FinancialReport(
        startDate: start,
        endDate: end,
        periodLabel: periodLabel,
        generatedAt: DateTime.now(),
        totalSpent: 0,
        dailySpends: const [],
        topExpenses: const [],
        topCategories: const [],
        reportsGeneratedCount: usageCount,
      );
      await ReportCacheService.store(userId, empty);
      return empty;
    }

    // Serialise to primitive maps — safe across Isolate boundary.
    final rawExpenses = allExpenses
        .map(_expenseToMap)
        .toList(growable: false);

    final activeRate     = CurrencyProvider.instance.activeRate;
    final activeCurrency = CurrencyProvider.instance.activeCurrency;

    // ── Background Isolate: aggregate ─────────────────────────────────────
    final report = await Isolate.run(
      () => _aggregate(
        rawExpenses:     rawExpenses,
        startDate:       start,
        endDate:         end,
        periodLabel:     periodLabel,
        activeRate:      activeRate,
        activeCurrency:  activeCurrency,
        usageCount:      usageCount,
      ),
    );

    await ReportCacheService.store(userId, report);
    return report;
  }

  /// Returns the earliest expense date for [userId], or null when no expenses.
  static DateTime? firstExpenseDate(int userId) {
    final dates = LocalStorageService.expenseBox.values
        .where((e) => e.userId == userId)
        .map((e) => DateUtils.dateOnly(e.date));
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

// ---------------------------------------------------------------------------
// Top-level helpers — must be top-level for Isolate.run()
// ---------------------------------------------------------------------------

FinancialReport _aggregate({
  required List<Map<String, dynamic>> rawExpenses,
  required DateTime startDate,
  required DateTime endDate,
  required String periodLabel,
  required double activeRate,
  required String activeCurrency,
  required int usageCount,
}) {
  double totalCop = 0;
  final dailyMap    = <String, double>{};
  final catAmounts  = <String, double>{};
  final catCounts   = <String, int>{};
  final weekdaySums = <int, double>{};

  for (final e in rawExpenses) {
    final amount   = (e['amount'] as num).toDouble();
    final dateStr  = (e['date'] as String).substring(0, 10);
    final category = e['primaryCategory'] as String? ?? 'Other';
    final weekday  = DateTime.parse(e['date'] as String).weekday;

    totalCop               += amount;
    dailyMap[dateStr]       = (dailyMap[dateStr] ?? 0) + amount;
    catAmounts[category]    = (catAmounts[category] ?? 0) + amount;
    catCounts[category]     = (catCounts[category] ?? 0) + 1;
    weekdaySums[weekday]    = (weekdaySums[weekday] ?? 0) + amount;
  }

  // Most active weekday by total spending.
  final mostActiveWeekday = weekdaySums.isEmpty
      ? null
      : weekdaySums.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;

  // Top 5 expenses.
  final sorted = List<Map<String, dynamic>>.from(rawExpenses)
    ..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));
  final top5 = sorted.take(5).map((e) {
    final amt = (e['amount'] as num).toDouble() * activeRate;
    return TopExpense(
      name: e['name'] as String? ?? 'Expense',
      amount: amt,
      category: e['primaryCategory'] as String? ?? 'Other',
      date: DateTime.parse(e['date'] as String),
    );
  }).toList();

  // Top 5 categories.
  final topCats = catAmounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top5Cats = topCats.take(5).map((entry) => CategoryTotal(
    label:  entry.key,
    amount: entry.value * activeRate,
    count:  catCounts[entry.key] ?? 0,
  )).toList();

  // Daily spends ascending.
  final daily = dailyMap.entries
      .map((e) => DailySpend(
            date:   DateTime.parse(e.key),
            amount: e.value * activeRate,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  return FinancialReport(
    startDate:              startDate,
    endDate:                endDate,
    periodLabel:            periodLabel,
    generatedAt:            DateTime.now(),
    totalSpent:             totalCop * activeRate,
    dailySpends:            daily,
    topExpenses:            top5,
    topCategories:          top5Cats,
    reportsGeneratedCount:  usageCount,
    mostActiveWeekday:      mostActiveWeekday,
  );
}

Map<String, dynamic> _expenseToMap(ExpenseModel e) => {
  'amount':          e.amount,
  'name':            e.name,
  'date':            e.date.toIso8601String(),
  'primaryCategory': e.primaryCategory,
};

String _buildLabel(DateTime start, DateTime end) {
  final fmt = DateFormat('MMM d');
  if (start.year == end.year) {
    return '${fmt.format(start)} – ${DateFormat('MMM d, y').format(end)}';
  }
  return '${DateFormat('MMM d, y').format(start)} – ${DateFormat('MMM d, y').format(end)}';
}
