import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
import '../services/app_navigation_service.dart';
import '../services/auth_memory_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_feed_service.dart';
import '../services/notifications_store.dart';
import '../theme/expense_visuals.dart';
import '../theme/spendant_theme.dart';
import '../widgets/spendant_delete_dialog.dart';
import 'new_expense_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final ValueListenable<Box<ExpenseModel>> _expensesListenable;
  late final ValueListenable<Box<GoalModel>> _goalsListenable;
  late final ValueListenable<Box<AppNotificationModel>>
  _notificationsListenable;
  late final int _notificationColorStartIndex;

  List<NotificationFeedItem> _notifications = <NotificationFeedItem>[];
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();
    _expensesListenable = LocalStorageService.expensesListenable;
    _goalsListenable = LocalStorageService.goalsListenable;
    _notificationsListenable = LocalStorageService.notificationsListenable;
    _notificationColorStartIndex = math.Random().nextInt(
      ExpenseVisuals.rotatingColors.length,
    );
    _expensesListenable.addListener(_handleStorageChanged);
    _goalsListenable.addListener(_handleStorageChanged);
    _notificationsListenable.addListener(_handleStorageChanged);
    _refreshNotifications();
  }

  @override
  void dispose() {
    _expensesListenable.removeListener(_handleStorageChanged);
    _goalsListenable.removeListener(_handleStorageChanged);
    _notificationsListenable.removeListener(_handleStorageChanged);
    super.dispose();
  }

  void _handleStorageChanged() {
    _refreshNotifications();
  }

  Future<void> _refreshNotifications() async {
    final notifications = NotificationFeedService.buildFeed(
      expenses: LocalStorageService.expenseBox.values,
      goals: LocalStorageService.goalBox.values,
      appNotifications: LocalStorageService.notificationBox.values,
      userId: _currentUserId,
    );

    if (mounted) {
      setState(() {
        _notifications = notifications;
      });
    }

    await NotificationsStore.markNotificationsAsViewed(
      notifications.map((notification) => notification.id),
    );
  }

  Future<void> _openExpenseEditor(NotificationFeedItem notification) async {
    final expense = notification.expense;
    if (expense == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewExpenseScreen(
          headerTitle: 'Edit Expense',
          editingExpense: expense,
        ),
      ),
    );

    await _refreshNotifications();
  }

  Future<bool> _showDeleteConfirmation({
    required String title,
    required String name,
  }) async {
    return showSpendAntDeleteDialog(context, title: title, name: name);
  }

  Future<void> _deleteExpense(NotificationFeedItem notification) async {
    final expense = notification.expense;
    if (expense == null) {
      return;
    }

    final shouldDelete = await _showDeleteConfirmation(
      title: 'Delete expense?',
      name: expense.name,
    );
    if (!shouldDelete || !mounted) {
      return;
    }

    final deletedFromCloud = await CloudSyncService().deleteExpenseRecord(
      expense,
    );
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(
            deletedFromCloud
                ? 'Expense deleted'
                : 'Expense deleted locally. Cloud cleanup is still pending.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    await _refreshNotifications();
  }

  Future<void> _openNotificationDetail(
    NotificationFeedItem notification,
  ) async {
    switch (notification.type) {
      case NotificationFeedType.expense:
        await _openExpenseEditor(notification);
        return;
      case NotificationFeedType.warning:
        if (notification.routeName != null) {
          await AppNavigationService.openRedirect(
            AppRedirect(
              routeName: notification.routeName!,
              routeArgumentInt: notification.routeArgumentInt,
            ),
          );
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _WarningDetailScreen(notification: notification),
          ),
        );
        return;
      case NotificationFeedType.goalCreated:
      case NotificationFeedType.goalHalfway:
      case NotificationFeedType.goalAchieved:
      case NotificationFeedType.incomeCreated:
      case NotificationFeedType.incomeDue:
      case NotificationFeedType.budgetWarning:
        final routeName = notification.routeName;
        if (routeName == null) {
          return;
        }
        await AppNavigationService.openRedirect(
          AppRedirect(
            routeName: routeName,
            routeArgumentInt: notification.routeArgumentInt,
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(_notifications);
    final userExpenses = LocalStorageService.expenseBox.values.where(
      (expense) => expense.userId == _currentUserId,
    );
    final reservedCategoryAccents = ExpenseVisuals.reservedAccentsForMonth(
      userExpenses,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _NotificationsHeader(onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: sections.isEmpty
                  ? const _EmptyNotificationsState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                      children: [
                        ...() {
                          var colorIndex = 0;
                          final widgets = <Widget>[];

                          for (final section in sections) {
                            widgets.add(
                              Text(
                                section.title,
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: AppPalette.ink,
                                ),
                              ),
                            );
                            widgets.add(const SizedBox(height: 12));

                            for (final item in section.items) {
                              widgets.add(
                                _NotificationCard(
                                  item: item,
                                  colorIndex: colorIndex++,
                                  colorStartIndex: _notificationColorStartIndex,
                                  reservedCategoryAccents:
                                      reservedCategoryAccents,
                                  onTap: () => _openNotificationDetail(item),
                                  onDelete:
                                      item.type == NotificationFeedType.expense
                                      ? () => _deleteExpense(item)
                                      : null,
                                  onEdit:
                                      item.type == NotificationFeedType.expense
                                      ? () => _openExpenseEditor(item)
                                      : null,
                                ),
                              );
                              widgets.add(const SizedBox(height: 12));
                            }

                            widgets.add(const SizedBox(height: 4));
                          }

                          return widgets;
                        }(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<_NotificationSection> _buildSections(
    List<NotificationFeedItem> notifications,
  ) {
    final todayItems = <NotificationFeedItem>[];
    final yesterdayItems = <NotificationFeedItem>[];
    final earlierItems = <NotificationFeedItem>[];

    for (final notification in notifications) {
      if (NotificationFeedService.isToday(notification.createdAt)) {
        todayItems.add(notification);
        continue;
      }
      if (NotificationFeedService.isYesterday(notification.createdAt)) {
        yesterdayItems.add(notification);
        continue;
      }
      earlierItems.add(notification);
    }

    final sections = <_NotificationSection>[];
    if (todayItems.isNotEmpty) {
      sections.add(_NotificationSection(title: 'Today', items: todayItems));
    }
    if (yesterdayItems.isNotEmpty) {
      sections.add(
        _NotificationSection(title: 'Yesterday', items: yesterdayItems),
      );
    }
    if (earlierItems.isNotEmpty) {
      sections.add(_NotificationSection(title: 'Earlier', items: earlierItems));
    }
    return sections;
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.green,
      padding: const EdgeInsets.fromLTRB(12, 50, 12, 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: AppPalette.ink),
          ),
          Expanded(
            child: Text(
              'Notifications',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.colorIndex,
    required this.colorStartIndex,
    required this.reservedCategoryAccents,
    required this.onTap,
    this.onDelete,
    this.onEdit,
  });

  final NotificationFeedItem item;
  final int colorIndex;
  final int colorStartIndex;
  final Map<String, ExpenseAccentVisual> reservedCategoryAccents;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final visuals = _NotificationVisuals.fromItem(
      item,
      colorIndex: colorIndex,
      colorStartIndex: colorStartIndex,
      reservedCategoryAccents: reservedCategoryAccents,
    );
    final showsExpenseActions = item.type == NotificationFeedType.expense;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: visuals.backgroundColor,
            borderRadius: BorderRadius.circular(2),
            border: const Border(
              bottom: BorderSide(color: Color(0xFFD0D0D0), width: 2),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: visuals.iconBackgroundColor,
                child: visuals.iconAssetPath != null
                    ? SvgPicture.asset(
                        visuals.iconAssetPath!,
                        width: 22,
                        height: 22,
                      )
                    : Icon(visuals.icon, color: AppPalette.ink, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NotificationFeedService.formatTimestamp(item.createdAt),
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.fieldHint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.amount != null)
                    Text(
                      NotificationFeedService.formatAmount(item.amount!),
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                  if (showsExpenseActions) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppPalette.ink,
                          ),
                          tooltip: 'Delete expense',
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          onPressed: onEdit,
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: AppPalette.ink,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    const Icon(
                      Icons.arrow_forward,
                      color: AppPalette.ink,
                      size: 21,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningDetailScreen extends StatelessWidget {
  const _WarningDetailScreen({required this.notification});

  final NotificationFeedItem notification;

  @override
  Widget build(BuildContext context) {
    final category = notification.category ?? 'Other';

    return _NotificationDetailShell(
      backgroundColor: const Color(0xFFFF632D),
      assetPath: 'web/ant/ant_suprised.svg',
      title: notification.detailTitle,
      body: notification.detailMessage,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE5DD),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _NotificationVisuals.warningIconBackground,
              child: notification.category != null
                  ? SvgPicture.asset(
                      ExpenseVisuals.iconAssetPathFor(category),
                      width: 22,
                      height: 22,
                    )
                  : const Icon(
                      Icons.warning_amber_rounded,
                      color: AppPalette.ink,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.expense?.name ?? 'Large expense',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink,
                    ),
                  ),
                  Text(
                    category,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (notification.amount != null)
              Text(
                NotificationFeedService.formatAmount(notification.amount!),
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.black54,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDetailShell extends StatelessWidget {
  const _NotificationDetailShell({
    required this.backgroundColor,
    required this.assetPath,
    required this.title,
    required this.body,
    this.child,
  });

  final Color backgroundColor;
  final String assetPath;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppPalette.ink),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SvgPicture.asset(
                      assetPath,
                      height: 240,
                      fit: BoxFit.contain,
                    ),
                    if (child != null) ...[const SizedBox(height: 22), child!],
                  ],
                ),
              ),
              SizedBox(
                width: 118,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset('web/ant/ant_idle.svg', height: 170),
            const SizedBox(height: 20),
            Text(
              'No notifications yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create expenses or complete goals and updates will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppPalette.fieldHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationSection {
  const _NotificationSection({required this.title, required this.items});

  final String title;
  final List<NotificationFeedItem> items;
}

class _NotificationVisuals {
  const _NotificationVisuals({
    required this.backgroundColor,
    required this.iconBackgroundColor,
    required this.icon,
    this.iconAssetPath,
  });

  static const Color warningIconBackground = Color(0xFF5AD070);

  final Color backgroundColor;
  final Color iconBackgroundColor;
  final IconData icon;
  final String? iconAssetPath;

  factory _NotificationVisuals.fromItem(
    NotificationFeedItem item, {
    required int colorIndex,
    required int colorStartIndex,
    required Map<String, ExpenseAccentVisual> reservedCategoryAccents,
  }) {
    final accentVisual =
        reservedCategoryAccents[item.category] ??
        ExpenseVisuals.rotatingAccent(
          itemIndex: colorIndex,
          startIndex: colorStartIndex,
        );

    switch (item.type) {
      case NotificationFeedType.expense:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.edit_outlined,
          iconAssetPath: ExpenseVisuals.iconAssetPathFor(
            item.category ?? 'Other',
          ),
        );
      case NotificationFeedType.warning:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.warning_amber_rounded,
        );
      case NotificationFeedType.goalCreated:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.flag_outlined,
        );
      case NotificationFeedType.goalHalfway:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.flag_circle_outlined,
        );
      case NotificationFeedType.goalAchieved:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.flag_outlined,
        );
      case NotificationFeedType.incomeCreated:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.account_balance_wallet_outlined,
        );
      case NotificationFeedType.incomeDue:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.payments_outlined,
        );
      case NotificationFeedType.budgetWarning:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.account_balance_wallet_outlined,
        );
    }
  }
}
