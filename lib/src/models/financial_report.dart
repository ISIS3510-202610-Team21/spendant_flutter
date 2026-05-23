import 'dart:convert';

/// Aggregated financial report for a custom date range.
///
/// Built by [ReportWorker] on a background Isolate, cached by
/// [ReportCacheService] with a 24-hour TTL.
class FinancialReport {
  const FinancialReport({
    required this.startDate,
    required this.endDate,
    required this.periodLabel,
    required this.generatedAt,
    required this.totalSpent,
    required this.dailySpends,
    required this.topExpenses,
    required this.topCategories,
    this.reportsGeneratedCount = 0,
    this.mostActiveWeekday,
    this.bqInsights = const [],
  });

  final DateTime startDate;
  final DateTime endDate;

  /// Human-readable label shown in the UI, e.g. "May 1 – May 22, 2026".
  final String periodLabel;

  final DateTime generatedAt;
  final double totalSpent;

  /// Daily totals for the histogram, sorted ascending by date.
  final List<DailySpend> dailySpends;

  /// Top 5 individual expenses by amount.
  final List<TopExpense> topExpenses;

  /// Top categories by total spending (up to 5).
  final List<CategoryTotal> topCategories;

  /// How many reports this user has generated in total (BQ: usage count).
  final int reportsGeneratedCount;

  /// Day-of-week (1=Mon…7=Sun) with most spending, null if not enough data.
  final int? mostActiveWeekday;

  /// Pre-computed BQ insight strings shown in the report UI.
  final List<String> bqInsights;

  // ---------------------------------------------------------------------------

  String get periodKey =>
      '${_d(startDate)}_${_d(endDate)}';

  static String _d(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'periodLabel': periodLabel,
    'generatedAt': generatedAt.toIso8601String(),
    'totalSpent': totalSpent,
    'dailySpends': dailySpends.map((d) => d.toJson()).toList(),
    'topExpenses': topExpenses.map((e) => e.toJson()).toList(),
    'topCategories': topCategories.map((c) => c.toJson()).toList(),
    'reportsGeneratedCount': reportsGeneratedCount,
    'mostActiveWeekday': mostActiveWeekday,
    'bqInsights': bqInsights,
  };

  factory FinancialReport.fromJson(Map<String, dynamic> json) =>
      FinancialReport(
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        periodLabel: json['periodLabel'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        totalSpent: (json['totalSpent'] as num).toDouble(),
        dailySpends: (json['dailySpends'] as List)
            .map((d) => DailySpend.fromJson(d as Map<String, dynamic>))
            .toList(),
        topExpenses: (json['topExpenses'] as List)
            .map((e) => TopExpense.fromJson(e as Map<String, dynamic>))
            .toList(),
        topCategories: (json['topCategories'] as List)
            .map((c) => CategoryTotal.fromJson(c as Map<String, dynamic>))
            .toList(),
        reportsGeneratedCount: json['reportsGeneratedCount'] as int? ?? 0,
        mostActiveWeekday: json['mostActiveWeekday'] as int?,
        bqInsights: (json['bqInsights'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );

  String toJsonString() => jsonEncode(toJson());

  static FinancialReport fromJsonString(String s) =>
      FinancialReport.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------

class DailySpend {
  const DailySpend({required this.date, required this.amount});
  final DateTime date;
  final double amount;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'amount': amount,
  };
  factory DailySpend.fromJson(Map<String, dynamic> json) => DailySpend(
    date: DateTime.parse(json['date'] as String),
    amount: (json['amount'] as num).toDouble(),
  );
}

// ---------------------------------------------------------------------------

class TopExpense {
  const TopExpense({
    required this.name,
    required this.amount,
    required this.category,
    required this.date,
  });
  final String name;
  final double amount;
  final String category;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'category': category,
    'date': date.toIso8601String(),
  };
  factory TopExpense.fromJson(Map<String, dynamic> json) => TopExpense(
    name: json['name'] as String,
    amount: (json['amount'] as num).toDouble(),
    category: json['category'] as String,
    date: DateTime.parse(json['date'] as String),
  );
}

// ---------------------------------------------------------------------------

class CategoryTotal {
  const CategoryTotal({
    required this.label,
    required this.amount,
    required this.count,
  });
  final String label;
  final double amount;
  final int count;

  Map<String, dynamic> toJson() => {
    'label': label,
    'amount': amount,
    'count': count,
  };
  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
    label: json['label'] as String,
    amount: (json['amount'] as num).toDouble(),
    count: json['count'] as int,
  );
}
