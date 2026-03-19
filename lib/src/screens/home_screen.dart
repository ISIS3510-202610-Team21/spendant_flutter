import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../models/expense_model.dart';
import '../services/daily_budget_service.dart';
import '../services/local_storage_service.dart';
import '../services/notifications_store.dart';
import '../theme/spendant_theme.dart';
import '../widgets/spendant_bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _defaultUserId = 1;
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');

  bool _hasUnreadNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    final hasUnread = await NotificationsStore.hasUnreadNotifications();
    if (!mounted) {
      return;
    }

    setState(() {
      _hasUnreadNotifications = hasUnread;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).pushNamed(AppRoutes.notifications);
    await _loadUnreadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final homeDependencies = Listenable.merge(<Listenable>[
      LocalStorageService.expensesListenable,
      LocalStorageService.incomesListenable,
      LocalStorageService.goalsListenable,
    ]);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }

        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.onboarding, (route) => false);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: AnimatedBuilder(
                animation: homeDependencies,
                builder: (context, _) {
                  final box = LocalStorageService.expenseBox;
                  final expenses =
                      box.values
                          .where((expense) => expense.userId == _defaultUserId)
                          .toList()
                        ..sort(
                          (left, right) => _expenseDateTime(
                            right,
                          ).compareTo(_expenseDateTime(left)),
                        );
                  final summary = DailyBudgetService.buildSummaryForUser(
                    _defaultUserId,
                  );

                  final monthTotal = _sumForMonth(expenses, DateTime.now());
                  final categoryStats = _buildCategoryStats(expenses);
                  final expenseGroups = _buildExpenseGroups(expenses);
                  final maxCategoryAmount = categoryStats.fold<double>(
                    0,
                    (current, stat) =>
                        current > stat.amount ? current : stat.amount,
                  );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                    children: [
                      Text(
                        'Your Budget for today',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _AmountHeadline(
                        amount: summary.remainingSpendableBudget <= 0
                            ? 0
                            : summary.remainingSpendableBudget,
                        amountColor: AppPalette.green,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'This month you have spent',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _AmountHeadline(
                        amount: monthTotal,
                        amountColor: AppPalette.expenseRed,
                        fontSize: 40,
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 260,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 18.0;
                            final width =
                                (constraints.maxWidth - (gap * 3)) / 4;

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final stat in categoryStats)
                                  SizedBox(
                                    width: width,
                                    child: _CategoryBarCard(
                                      stat: stat,
                                      maxAmount: maxCategoryAmount,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (expenseGroups.isEmpty) const _EmptyExpensesCard(),
                      for (final group in expenseGroups) ...[
                        Text(
                          group.title,
                          style: GoogleFonts.nunito(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.ink,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final entry in group.entries) ...[
                          _ExpenseListTile(entry: entry),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  );
                },
              ),
            ),
            const SpendAntBottomNav(currentItem: SpendAntNavItem.home),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: AppPalette.green,
      padding: const EdgeInsets.fromLTRB(16, 58, 16, 14),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _openNotifications,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.notifications_none_outlined,
                      color: AppPalette.ink,
                      size: 28,
                    ),
                    if (_hasUnreadNotifications)
                      Positioned(
                        right: 1,
                        top: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF7A2F),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Home',
            style: GoogleFonts.nunito(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }

  double _sumForMonth(List<ExpenseModel> expenses, DateTime day) {
    return expenses
        .where(
          (expense) =>
              expense.date.year == day.year && expense.date.month == day.month,
        )
        .fold(0, (total, expense) => total + expense.amount);
  }

  List<_CategoryStat> _buildCategoryStats(List<ExpenseModel> expenses) {
    final monthExpenses = expenses.where((expense) {
      final now = DateTime.now();
      return expense.date.year == now.year && expense.date.month == now.month;
    });

    final totals = <String, double>{
      'Food': 0,
      'Transport': 0,
      'Services': 0,
      'Other': 0,
    };

    for (final expense in monthExpenses) {
      final category = _normalizeCategory(expense.primaryCategory);
      totals[category] = (totals[category] ?? 0) + expense.amount;
    }

    return <_CategoryStat>[
      _CategoryStat.fromKey('Food', totals['Food'] ?? 0),
      _CategoryStat.fromKey('Transport', totals['Transport'] ?? 0),
      _CategoryStat.fromKey('Services', totals['Services'] ?? 0),
      _CategoryStat.fromKey('Other', totals['Other'] ?? 0),
    ];
  }

  List<_ExpenseDayGroup> _buildExpenseGroups(List<ExpenseModel> expenses) {
    final grouped = <DateTime, List<ExpenseModel>>{};

    for (final expense in expenses) {
      final dateOnly = DateTime(
        expense.date.year,
        expense.date.month,
        expense.date.day,
      );
      grouped.putIfAbsent(dateOnly, () => <ExpenseModel>[]).add(expense);
    }

    final orderedDates = grouped.keys.toList()
      ..sort((left, right) => right.compareTo(left));

    return orderedDates.take(6).map((date) {
      final dayExpenses = grouped[date]!
        ..sort(
          (left, right) =>
              _expenseDateTime(right).compareTo(_expenseDateTime(left)),
        );

      return _ExpenseDayGroup(
        title: _titleForDate(date),
        entries: dayExpenses.map(_buildExpenseEntry).toList(),
      );
    }).toList();
  }

  _ExpenseEntry _buildExpenseEntry(ExpenseModel expense) {
    final category = _normalizeCategory(expense.primaryCategory);
    final detailLabel = expense.detailLabels.isNotEmpty
        ? expense.detailLabels.first
        : category;
    final visual = _CategoryVisuals.of(category);

    return _ExpenseEntry(
      name: expense.name,
      category: detailLabel,
      amount: 'COP ${_currencyFormat.format(expense.amount.round())}',
      color: visual.tileColor,
      iconAssetPath: visual.iconAssetPath,
      iconColor: visual.color,
    );
  }

  String _normalizeCategory(String? category) {
    switch (category?.trim()) {
      case 'Food':
        return 'Food';
      case 'Transport':
        return 'Transport';
      case 'Services':
        return 'Services';
      default:
        return 'Other';
    }
  }

  String _titleForDate(DateTime date) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (_isSameDay(date, now)) {
      return 'Today Expenses';
    }
    if (_isSameDay(date, yesterday)) {
      return 'Yesterday Expenses';
    }

    final daysDifference = now.difference(date).inDays;
    if (daysDifference < 7) {
      return '${DateFormat('EEEE').format(date)} Expenses';
    }

    return '${DateFormat('d/M/y').format(date)} Expenses';
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  DateTime _expenseDateTime(ExpenseModel expense) {
    final parts = expense.time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
      hour,
      minute,
    );
  }
}

class _AmountHeadline extends StatelessWidget {
  const _AmountHeadline({
    required this.amount,
    required this.amountColor,
    this.fontSize = 44,
  });

  final double amount;
  final Color amountColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final formattedAmount = NumberFormat(
      '#,###',
      'en_US',
    ).format(amount.round());

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '\$$formattedAmount ',
            style: GoogleFonts.nunito(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: amountColor,
            ),
          ),
          TextSpan(
            text: 'COP',
            style: GoogleFonts.nunito(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppPalette.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBarCard extends StatelessWidget {
  const _CategoryBarCard({required this.stat, required this.maxAmount});

  final _CategoryStat stat;
  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    const minHeight = 92.0;
    const maxHeight = 248.0;
    final progress = maxAmount <= 0 ? 0.0 : stat.amount / maxAmount;
    final height = minHeight + ((maxHeight - minHeight) * progress);

    return SizedBox(
      height: maxHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: stat.color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SvgPicture.asset(
                stat.iconAssetPath,
                width: 30,
                height: 30,
                colorFilter: const ColorFilter.mode(
                  AppPalette.ink,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  stat.label,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseListTile extends StatelessWidget {
  const _ExpenseListTile({required this.entry});

  final _ExpenseEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: entry.color,
        borderRadius: BorderRadius.circular(2),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFD0D0D0), width: 2),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: entry.iconColor,
            child: SvgPicture.asset(
              entry.iconAssetPath,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                AppPalette.ink,
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.category,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            entry.amount,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExpensesCard extends StatelessWidget {
  const _EmptyExpensesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'No local expenses yet. Add one with the + button and it will appear here immediately, even without internet.',
        textAlign: TextAlign.center,
        style: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppPalette.ink,
        ),
      ),
    );
  }
}

class _CategoryStat {
  const _CategoryStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.iconAssetPath,
  });

  factory _CategoryStat.fromKey(String key, double amount) {
    final visual = _CategoryVisuals.of(key);
    return _CategoryStat(
      label: key,
      amount: amount,
      color: visual.color,
      iconAssetPath: visual.iconAssetPath,
    );
  }

  final String label;
  final double amount;
  final Color color;
  final String iconAssetPath;
}

class _ExpenseDayGroup {
  const _ExpenseDayGroup({required this.title, required this.entries});

  final String title;
  final List<_ExpenseEntry> entries;
}

class _ExpenseEntry {
  const _ExpenseEntry({
    required this.name,
    required this.category,
    required this.amount,
    required this.color,
    required this.iconAssetPath,
    required this.iconColor,
  });

  final String name;
  final String category;
  final String amount;
  final Color color;
  final String iconAssetPath;
  final Color iconColor;
}

class _CategoryVisual {
  const _CategoryVisual({
    required this.color,
    required this.tileColor,
    required this.iconAssetPath,
  });

  final Color color;
  final Color tileColor;
  final String iconAssetPath;
}

abstract final class _CategoryVisuals {
  static const Map<String, _CategoryVisual> _values = <String, _CategoryVisual>{
    'Food': _CategoryVisual(
      color: AppPalette.food,
      tileColor: Color(0xFFCFE2FF),
      iconAssetPath: 'web/icons/Food.svg',
    ),
    'Transport': _CategoryVisual(
      color: AppPalette.transport,
      tileColor: Color(0xFFF6D1C4),
      iconAssetPath: 'web/icons/Transport.svg',
    ),
    'Services': _CategoryVisual(
      color: AppPalette.services,
      tileColor: Color(0xFFF7E5A8),
      iconAssetPath: 'web/icons/Services.svg',
    ),
    'Other': _CategoryVisual(
      color: AppPalette.other,
      tileColor: Color(0xFFFBC5C4),
      iconAssetPath: 'web/icons/Other.svg',
    ),
  };

  static _CategoryVisual of(String category) {
    return _values[category] ?? _values['Other']!;
  }
}
