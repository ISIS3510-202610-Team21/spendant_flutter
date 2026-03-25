import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../app.dart';
import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../services/app_date_format_service.dart';
import '../services/app_analytics_service.dart';
import '../services/auth_memory_store.dart';
import '../services/daily_budget_service.dart';
import '../services/expense_moment_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_feed_service.dart';
import '../services/notifications_store.dart';
import '../theme/expense_visuals.dart';
import '../theme/spendant_theme.dart';
import '../widgets/spendant_bottom_nav.dart';
import 'new_expense_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final NumberFormat _currencyFormat = NumberFormat('#,###', 'en_US');
  static const Duration _exitConfirmWindow = Duration(seconds: 2);

  bool _hasUnreadNotifications = true;
  DateTime? _lastBackPressAt;
  late final ValueListenable<Box<ExpenseModel>> _expensesListenable;
  late final ValueListenable<Box<GoalModel>> _goalsListenable;
  late final ValueListenable<Box<AppNotificationModel>>
  _notificationsListenable;
  late final int _expenseColorStartIndex;
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();
    _expensesListenable = LocalStorageService.expensesListenable;
    _goalsListenable = LocalStorageService.goalsListenable;
    _notificationsListenable = LocalStorageService.notificationsListenable;
    _expenseColorStartIndex = math.Random().nextInt(
      ExpenseVisuals.rotatingColors.length,
    );
    _expensesListenable.addListener(_handleNotificationSourcesChanged);
    _goalsListenable.addListener(_handleNotificationSourcesChanged);
    _notificationsListenable.addListener(_handleNotificationSourcesChanged);
    _loadUnreadNotifications();
    unawaited(
      AppAnalyticsService.instance.logAllBusinessQuestions(
        userId: _currentUserId,
      ),
    );
  }

  @override
  void dispose() {
    _expensesListenable.removeListener(_handleNotificationSourcesChanged);
    _goalsListenable.removeListener(_handleNotificationSourcesChanged);
    _notificationsListenable.removeListener(_handleNotificationSourcesChanged);
    super.dispose();
  }

  void _handleNotificationSourcesChanged() {
    _loadUnreadNotifications();
  }

  Future<void> _loadUnreadNotifications() async {
    final notifications = NotificationFeedService.buildFeed(
      expenses: LocalStorageService.expenseBox.values,
      goals: LocalStorageService.goalBox.values,
      appNotifications: LocalStorageService.notificationBox.values,
      userId: _currentUserId,
    );
    final hasUnread = await NotificationsStore.hasUnreadNotifications(
      notificationIds: notifications.map((notification) => notification.id),
    );
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

  Future<void> _openExpenseDetail(ExpenseModel expense) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewExpenseScreen(
          headerTitle: 'Edit Expense',
          editingExpense: expense,
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log out?'),
          content: const Text(
            'You will return to the onboarding screen and this session will be closed on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) {
      return;
    }

    await AuthMemoryStore.clearSession();
    if (!mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.onboarding, (route) => false);
  }

  Future<void> _handleBackPressed() async {
    final now = DateTime.now();
    final previousBackPress = _lastBackPressAt;
    if (previousBackPress != null &&
        now.difference(previousBackPress) <= _exitConfirmWindow) {
      await SystemNavigator.pop();
      return;
    }

    _lastBackPressAt = now;
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Press back again to exit SpendAnt.'),
        duration: Duration(seconds: 2),
      ),
    );
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
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }

        await _handleBackPressed();
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
                          .where(
                            (expense) =>
                                expense.userId == _currentUserId &&
                                !ExpenseMomentService.isFutureExpense(expense),
                          )
                          .toList()
                        ..sort(
                          (left, right) => _expenseDateTime(
                            right,
                          ).compareTo(_expenseDateTime(left)),
                        );

                  final summary = DailyBudgetService.buildSummaryForUser(
                    _currentUserId,
                  );

                  final monthTotal = _sumForMonth(expenses, DateTime.now());
                  final categoryStats = _buildCategoryStats(expenses);
                  final prioritizedLabels = categoryStats
                      .map((stat) => stat.label)
                      .toList(growable: false);
                  final reservedCategoryAccents = _buildReservedCategoryAccents(
                    categoryStats,
                  );
                  final expenseGroups = _buildExpenseGroups(
                    expenses,
                    prioritizedLabels,
                    reservedCategoryAccents,
                  );
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
                        amount: summary.spendableDailyBudget,
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
                      if (categoryStats.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 260,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final itemCount = categoryStats.length;
                              const gap = 18.0;
                              final totalGap = gap * (itemCount - 1);
                              final availableWidth =
                                  constraints.maxWidth - totalGap;
                              final itemWidth = math.min(
                                110.0,
                                availableWidth / itemCount,
                              );

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (
                                    var index = 0;
                                    index < itemCount;
                                    index++
                                  ) ...[
                                    SizedBox(
                                      width: itemWidth,
                                      child: _CategoryBarCard(
                                        stat: categoryStats[index],
                                        maxAmount: maxCategoryAmount,
                                      ),
                                    ),
                                    if (index < itemCount - 1)
                                      const SizedBox(width: gap),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 22),
                      ] else
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
                          _ExpenseListTile(
                            entry: entry,
                            onTap: () => _openExpenseDetail(entry.expense),
                          ),
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
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.logout_rounded,
                  color: AppPalette.ink,
                  size: 26,
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
    final visibleEntries = ExpenseVisuals.topCategoryTotalsForMonth(expenses);

    return List<_CategoryStat>.generate(visibleEntries.length, (index) {
      final entry = visibleEntries[index];
      return _CategoryStat(
        label: entry.label,
        amount: entry.amount,
        color: ExpenseVisuals.reservedChartColors[index],
        iconAssetPath: ExpenseVisuals.iconAssetPathFor(entry.label),
      );
    });
  }

  List<_ExpenseDayGroup> _buildExpenseGroups(
    List<ExpenseModel> expenses,
    List<String> prioritizedLabels,
    Map<String, ExpenseAccentVisual> reservedCategoryAccents,
  ) {
    final grouped = <DateTime, List<ExpenseModel>>{};

    for (final expense in expenses) {
      final dateOnly = DateTime(
        expense.date.year,
        expense.date.month,
        expense.date.day,
      );
      grouped.putIfAbsent(dateOnly, () => <ExpenseModel>[]).add(expense);
    }

    final orderedDates = grouped.keys.toList()..sort(_compareExpenseGroupDates);

    var colorIndex = 0;

    return orderedDates.take(6).map((date) {
      final dayExpenses = grouped[date]!
        ..sort(
          (left, right) =>
              _expenseDateTime(right).compareTo(_expenseDateTime(left)),
        );

      return _ExpenseDayGroup(
        title: _titleForDate(date),
        entries: dayExpenses
            .map(
              (expense) => _buildExpenseEntry(
                expense,
                colorIndex++,
                prioritizedLabels,
                reservedCategoryAccents,
              ),
            )
            .toList(),
      );
    }).toList();
  }

  _ExpenseEntry _buildExpenseEntry(
    ExpenseModel expense,
    int colorIndex,
    List<String> prioritizedLabels,
    Map<String, ExpenseAccentVisual> reservedCategoryAccents,
  ) {
    final detailLabel = ExpenseVisuals.resolveDisplayLabel(
      expense,
      prioritizedLabels: prioritizedLabels,
    );
    final accentVisual =
        reservedCategoryAccents[detailLabel] ??
        ExpenseVisuals.rotatingAccent(
          itemIndex: colorIndex,
          startIndex: _expenseColorStartIndex,
        );

    return _ExpenseEntry(
      expense: expense,
      name: expense.name,
      category: detailLabel,
      amount: 'COP ${_currencyFormat.format(expense.amount.round())}',
      color: accentVisual.backgroundColor,
      iconAssetPath: ExpenseVisuals.iconAssetPathFor(detailLabel),
      iconColor: accentVisual.accentColor,
    );
  }

  Map<String, ExpenseAccentVisual> _buildReservedCategoryAccents(
    List<_CategoryStat> categoryStats,
  ) {
    return <String, ExpenseAccentVisual>{
      for (final stat in categoryStats)
        stat.label: ExpenseVisuals.accentFromColor(stat.color),
    };
  }

  String _titleForDate(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    if (_isSameDay(date, today)) {
      return 'Today Expenses';
    }
    if (_isSameDay(date, yesterday)) {
      return 'Yesterday Expenses';
    }
    if (_isSameDay(date, tomorrow)) {
      return 'Tomorrow Expenses';
    }
    if (date.isAfter(today)) {
      return '${AppDateFormatService.longDate(date)} Expenses';
    }

    final daysDifference = today.difference(date).inDays;
    if (daysDifference < 7) {
      return '${DateFormat('EEEE').format(date)} Expenses';
    }

    return '${AppDateFormatService.longDate(date)} Expenses';
  }

  int _compareExpenseGroupDates(DateTime left, DateTime right) {
    final today = DateUtils.dateOnly(DateTime.now());
    final leftDate = DateUtils.dateOnly(left);
    final rightDate = DateUtils.dateOnly(right);

    final leftIsToday = _isSameDay(leftDate, today);
    final rightIsToday = _isSameDay(rightDate, today);
    if (leftIsToday != rightIsToday) {
      return leftIsToday ? -1 : 1;
    }

    final leftIsFuture = leftDate.isAfter(today);
    final rightIsFuture = rightDate.isAfter(today);
    if (leftIsFuture != rightIsFuture) {
      return leftIsFuture ? 1 : -1;
    }

    if (leftIsFuture && rightIsFuture) {
      return leftDate.compareTo(rightDate);
    }

    return rightDate.compareTo(leftDate);
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
              SvgPicture.asset(stat.iconAssetPath, width: 30, height: 30),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  stat.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                    height: 1,
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
  const _ExpenseListTile({required this.entry, required this.onTap});

  final _ExpenseEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
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
        ),
      ),
    );
  }
}

class _EmptyExpensesCard extends StatelessWidget {
  const _EmptyExpensesCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          'No expenses yet.\nTap + to add one.',
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppPalette.fieldHint,
            height: 1.5,
          ),
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
    required this.expense,
    required this.name,
    required this.category,
    required this.amount,
    required this.color,
    required this.iconAssetPath,
    required this.iconColor,
  });

  final ExpenseModel expense;
  final String name;
  final String category;
  final String amount;
  final Color color;
  final String iconAssetPath;
  final Color iconColor;
}
