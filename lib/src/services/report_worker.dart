import 'dart:isolate';

import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

import '../models/expense_model.dart';
import '../models/financial_report.dart';
import '../services/auth_memory_store.dart';
import '../services/currency_provider.dart';
import '../services/daily_budget_service.dart';
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

    // ── BQ1: days since last expense (all-time, main thread) ─────────────
    final allUserExpenses = LocalStorageService.expenseBox.values
        .where((e) => e.userId == userId)
        .toList();
    final daysSinceLastExpense = _daysSinceLastExpense(allUserExpenses);

    // ── BQ4: small recurring expenses in last 3 months (main thread) ─────
    final smallRecurring3m = _smallRecurringLast3Months(allUserExpenses);

    // ── BQ7: savings goal progress (needs Hive goalBox — main thread) ────
    double savingsAchievedPct = -1;
    int savingsGoalCount = 0;
    try {
      final goals = LocalStorageService.goalBox.values
          .where((g) => g.userId == userId)
          .toList();
      if (goals.isNotEmpty) {
        final summary = DailyBudgetService.buildSummaryForUser(userId);
        double totalPct = 0;
        int validGoals = 0;
        for (final goal in goals) {
          final state = summary.stateFor(goal);
          if (state == null || goal.targetAmount <= 0) continue;
          totalPct += ((state.currentAmount / goal.targetAmount) * 100)
              .clamp(0.0, 100.0);
          validGoals++;
        }
        if (validGoals > 0) {
          savingsAchievedPct = totalPct / validGoals;
          savingsGoalCount = validGoals;
        }
      }
    } catch (_) {}

    // ── BQ8: budget midpoint consumption (needs DailyBudgetService) ──────
    double budgetConsumedPct = -1;
    bool budgetEvaluatedAtMidpoint = false;
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthExpenses = allUserExpenses
          .where((e) => !e.date.isBefore(monthStart) && !e.date.isAfter(now))
          .toList();
      if (monthExpenses.isNotEmpty) {
        final summary = DailyBudgetService.buildSummaryForUser(userId);
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final monthlyBudget = summary.internalDailyBudget * daysInMonth;
        if (monthlyBudget > 0) {
          final consumed =
              monthExpenses.fold<double>(0, (s, e) => s + e.amount);
          budgetConsumedPct =
              (consumed / monthlyBudget * 100).clamp(0.0, 200.0);
          budgetEvaluatedAtMidpoint = now.day >= (daysInMonth ~/ 2);
        }
      }
    } catch (_) {}

    // ── BQ9: highest category spending growth vs previous month ──────────
    // Uses all-time expenses — computed on main thread, passed as primitives.
    String? topGrowthCategory;
    double topGrowthCurrentCop = 0;
    double topGrowthPreviousCop = 0;
    double topGrowthPercent = 0;
    try {
      final now = DateTime.now();
      final thisStart = DateTime(now.year, now.month, 1);
      final lastStart = DateTime(now.year, now.month - 1, 1);
      final lastEnd =
          DateTime(now.year, now.month - 1, now.day, 23, 59, 59);

      Map<String, double> sumByCat(DateTime from, DateTime to) {
        final totals = <String, double>{};
        for (final e in allUserExpenses) {
          if (e.date.isBefore(from) || e.date.isAfter(to)) continue;
          final cat = e.primaryCategory ?? 'Other';
          totals[cat] = (totals[cat] ?? 0) + e.amount;
        }
        return totals;
      }

      final thisPeriod = sumByCat(thisStart, now);
      final lastPeriod = sumByCat(lastStart, lastEnd);
      double topGrowthPct = double.negativeInfinity;

      for (final entry in thisPeriod.entries) {
        final prev = lastPeriod[entry.key] ?? 0;
        final growth = prev > 0
            ? ((entry.value - prev) / prev) * 100
            : entry.value > 0
                ? 100.0
                : 0.0;
        if (growth > topGrowthPct) {
          topGrowthPct = growth;
          topGrowthCategory = entry.key;
          topGrowthCurrentCop = entry.value;
          topGrowthPreviousCop = prev;
          topGrowthPercent = growth;
        }
      }
    } catch (_) {}

    // Serialise to primitive maps — safe across Isolate boundary.
    final rawExpenses = allExpenses
        .map(_expenseToMap)
        .toList(growable: false);

    final activeRate     = CurrencyProvider.instance.activeRate;
    final activeCurrency = CurrencyProvider.instance.activeCurrency;

    // ── Background Isolate: aggregate ─────────────────────────────────────
    final report = await Isolate.run(
      () => _aggregate(
        rawExpenses:             rawExpenses,
        startDate:               start,
        endDate:                 end,
        periodLabel:             periodLabel,
        activeRate:              activeRate,
        activeCurrency:          activeCurrency,
        usageCount:              usageCount,
        daysSinceLastExpense:    daysSinceLastExpense,
        smallRecurring3m:        smallRecurring3m,
        savingsAchievedPct:      savingsAchievedPct,
        savingsGoalCount:        savingsGoalCount,
        budgetConsumedPct:       budgetConsumedPct,
        budgetEvaluatedAtMidpoint: budgetEvaluatedAtMidpoint,
        topGrowthCategory:       topGrowthCategory,
        topGrowthCurrentCop:     topGrowthCurrentCop,
        topGrowthPreviousCop:    topGrowthPreviousCop,
        topGrowthPercent:        topGrowthPercent,
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
  required int daysSinceLastExpense,
  required int smallRecurring3m,
  required double savingsAchievedPct,
  required int savingsGoalCount,
  required double budgetConsumedPct,
  required bool budgetEvaluatedAtMidpoint,
  required String? topGrowthCategory,
  required double topGrowthCurrentCop,
  required double topGrowthPreviousCop,
  required double topGrowthPercent,
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

  // Fill every calendar day in the range so the histogram has no gaps.
  var cursor = startDate;
  while (!cursor.isAfter(endDate)) {
    final k = '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
    dailyMap.putIfAbsent(k, () => 0);
    cursor = cursor.add(const Duration(days: 1));
  }

  // Daily spends ascending.
  final daily = dailyMap.entries
      .map((e) => DailySpend(
            date:   DateTime.parse(e.key),
            amount: e.value * activeRate,
          ))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  // ── BQ2: OCR usage rate ───────────────────────────────────────────────
  final ocrCount  = rawExpenses.where((e) => e['source'] == 'OCR').length;
  final total     = rawExpenses.length;
  final ocrPct    = total > 0 ? ((ocrCount / total) * 100).round() : 0;

  // ── BQ3: most common registration hour ───────────────────────────────
  final hourCounts = <int, int>{};
  for (final e in rawExpenses) {
    final t = e['time'] as String?;
    if (t != null && t.length >= 2) {
      final h = int.tryParse(t.substring(0, 2));
      if (h != null) hourCounts[h] = (hourCounts[h] ?? 0) + 1;
    }
  }
  String? mostActiveHourLabel;
  if (hourCounts.isNotEmpty) {
    final h = hourCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final suffix = h < 12 ? 'AM' : 'PM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    mostActiveHourLabel = '$h12:00 $suffix';
  }

  // ── Spending advice: highest single expense in period ────────────────
  String? highestExpenseNote;
  if (top5.isNotEmpty) {
    final top = top5.first;
    highestExpenseNote =
        'Highest expense: ${top.name} — $activeCurrency ${_fmtNum(top.amount)}';
  }

  // ── Spending advice: average daily spending ───────────────────────────
  final periodDays = endDate.difference(startDate).inDays + 1;
  final avgDaily   = periodDays > 0 ? (totalCop * activeRate) / periodDays : 0.0;

  // ── Micro-expenses (< 5000 COP equivalent) in period ─────────────────
  final microCount = rawExpenses
      .where((e) => (e['amount'] as num).toDouble() < 5000)
      .length;

  // ── Build ordered BQ insight lines ───────────────────────────────────
  final insights = <String>[];

  // BQ1
  if (daysSinceLastExpense >= 0) {
    insights.add(daysSinceLastExpense == 0
        ? 'You registered an expense today'
        : '$daysSinceLastExpense ${daysSinceLastExpense == 1 ? 'day' : 'days'} since your last registered expense');
  }

  // BQ2 — OCR edit rate proxy
  if (total > 0) {
    insights.add('$ocrPct% of expenses in this period were captured with OCR scanning ($ocrCount of $total)');
  }

  // BQ3
  if (mostActiveHourLabel != null) {
    insights.add('Most common registration time in this period: $mostActiveHourLabel');
  }

  // BQ4
  if (smallRecurring3m > 0) {
    insights.add('$smallRecurring3m small recurring ${smallRecurring3m == 1 ? 'expense' : 'expenses'} in the last 3 months');
  }

  // BQ7 — Savings goal progress
  if (savingsAchievedPct >= 0) {
    final pct = savingsAchievedPct.round();
    final onTrack = savingsAchievedPct >= 50;
    insights.add(
      'Savings goals: $pct% achieved on average across '
      '$savingsGoalCount active ${savingsGoalCount == 1 ? 'goal' : 'goals'} '
      '(${onTrack ? 'on track' : 'behind target'})',
    );
  }

  // BQ8 — Budget midpoint consumption
  if (budgetConsumedPct >= 0) {
    final pct = budgetConsumedPct.round();
    if (budgetEvaluatedAtMidpoint && budgetConsumedPct > 50) {
      insights.add(
        'Monthly budget: $pct% consumed past the midpoint — overspending risk',
      );
    } else {
      insights.add('Monthly budget: $pct% consumed so far this month');
    }
  }

  // BQ9 — Highest category growth vs previous month
  if (topGrowthCategory != null) {
    if (topGrowthPreviousCop == 0) {
      insights.add(
        'New spending category this month: $topGrowthCategory '
        '($activeCurrency ${_fmtNum(topGrowthCurrentCop * activeRate)})',
      );
    } else {
      final pct = topGrowthPercent.round();
      insights.add(
        'Highest category growth: $topGrowthCategory +$pct% vs last month '
        '($activeCurrency ${_fmtNum(topGrowthCurrentCop * activeRate)})',
      );
    }
  }

  // Spending advice insights
  if (highestExpenseNote != null) insights.add(highestExpenseNote);

  if (microCount > 0) {
    insights.add('$microCount small purchases under $activeCurrency ${_fmtNum(5000 * activeRate)} in this period');
  }

  if (avgDaily > 0 && periodDays > 1) {
    insights.add('Average daily spending: $activeCurrency ${_fmtNum(avgDaily)}');
  }

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
    bqInsights:             insights,
  );
}

Map<String, dynamic> _expenseToMap(ExpenseModel e) => {
  'amount':          e.amount,
  'name':            e.name,
  'date':            e.date.toIso8601String(),
  'time':            e.time,                      // "HH:mm" for most-active-hour
  'primaryCategory': e.primaryCategory,
  'source':          e.source,                    // 'MANUAL' | 'OCR' | 'GOOGLE_PAY'
  'isRecurring':     e.isRecurring,               // small recurring BQ
};

// Helper: days since last expense across ALL user expenses (main thread).
int _daysSinceLastExpense(List<ExpenseModel> allExpenses) {
  if (allExpenses.isEmpty) return -1;
  final latest = allExpenses
      .map((e) => e.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return DateTime.now().difference(DateUtils.dateOnly(latest)).inDays;
}

// Helper: small recurring expense count in last 3 months (main thread).
int _smallRecurringLast3Months(List<ExpenseModel> allExpenses) {
  final cutoff = DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 90));
  return allExpenses
      .where((e) => e.isRecurring && e.amount < 50000 && !e.date.isBefore(cutoff))
      .length;
}

// Format number for insight strings (no currency provider — top-level fn).
String _fmtNum(double v) {
  if (v >= 1000) {
    // Simple thousands separator without intl
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
  final s = v.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'\.?0+$'), '');
}

String _buildLabel(DateTime start, DateTime end) {
  final fmt = DateFormat('MMM d');
  if (start.year == end.year) {
    return '${fmt.format(start)} – ${DateFormat('MMM d, y').format(end)}';
  }
  return '${DateFormat('MMM d, y').format(start)} – ${DateFormat('MMM d, y').format(end)}';
}
