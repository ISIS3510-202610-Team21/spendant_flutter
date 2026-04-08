import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../models/app_notification_model.dart';
import '../models/expense_model.dart';
import '../services/app_navigation_service.dart';
import '../services/app_notification_service.dart';
import '../services/auto_categorization_service.dart';
import '../services/auth_memory_store.dart';
import '../services/google_pay_expense_import_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_feed_service.dart';
import '../services/notifications_store.dart';
import '../services/post_auth_navigation.dart';
import '../theme/expense_visuals.dart';
import '../theme/spendant_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final ValueListenable<Box<ExpenseModel>> _expensesListenable;
  late final ValueListenable<Box<AppNotificationModel>>
  _notificationsListenable;
  late final int _notificationColorStartIndex;

  List<NotificationFeedItem> _notifications = <NotificationFeedItem>[];
  bool _isSimulatingGooglePay = false;
  int get _currentUserId => AuthMemoryStore.currentUserIdOrGuest;

  @override
  void initState() {
    super.initState();
    _expensesListenable = LocalStorageService.expensesListenable;
    _notificationsListenable = LocalStorageService.notificationsListenable;
    _notificationColorStartIndex = math.Random().nextInt(
      ExpenseVisuals.rotatingColors.length,
    );
    _expensesListenable.addListener(_handleStorageChanged);
    _notificationsListenable.addListener(_handleStorageChanged);
    _refreshNotifications();
  }

  @override
  void dispose() {
    _expensesListenable.removeListener(_handleStorageChanged);
    _notificationsListenable.removeListener(_handleStorageChanged);
    super.dispose();
  }

  void _handleStorageChanged() {
    _refreshNotifications();
  }

  Future<void> _refreshNotifications() async {
    await AutoCategorizationService.instance.backfillPendingExpenseCategories(
      expenses: LocalStorageService.expenseBox.values.where(
        (expense) => expense.userId == _currentUserId,
      ),
    );

    final notifications = NotificationFeedService.buildFeed(
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

  Future<void> _simulateGooglePayExpenseImport() async {
    if (_isSimulatingGooglePay) {
      return;
    }

    setState(() {
      _isSimulatingGooglePay = true;
    });

    final result = await GooglePayExpenseImportService.simulateExpenseImport();
    if (result.imported) {
      await AppNotificationService.refresh();
    }
    await _refreshNotifications();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSimulatingGooglePay = false;
    });

    final parsedExpense = result.expense;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (result.status) {
      case GooglePayImportStatus.imported:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              parsedExpense == null
                  ? 'Simulated Google Pay expense imported.'
                  : 'Imported ${parsedExpense.name} for ${NotificationFeedService.formatAmount(parsedExpense.amount)}.',
            ),
          ),
        );
        return;
      case GooglePayImportStatus.duplicate:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'That simulated Google Pay expense already exists nearby.',
            ),
          ),
        );
        return;
      case GooglePayImportStatus.ignored:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'The simulated Google Pay notification could not be parsed.',
            ),
          ),
        );
        return;
      case GooglePayImportStatus.unavailable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Sign in first to import a simulated Google Pay expense.',
            ),
          ),
        );
        return;
    }
  }

  Future<void> _openNotificationDetail(
    NotificationFeedItem notification,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _NotificationDetailDialog(notification: notification),
    );
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
            _NotificationsHeader(
              onClose: () => Navigator.of(context).pop(),
              onHiddenAction: _simulateGooglePayExpenseImport,
            ),
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
  const _NotificationsHeader({
    required this.onClose,
    required this.onHiddenAction,
  });

  final VoidCallback onClose;
  final VoidCallback onHiddenAction;

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
          GestureDetector(
            onLongPress: onHiddenAction,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox(width: 48, height: 48),
          ),
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
  });

  final NotificationFeedItem item;
  final int colorIndex;
  final int colorStartIndex;
  final Map<String, ExpenseAccentVisual> reservedCategoryAccents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visuals = _NotificationVisuals.fromItem(
      item,
      colorIndex: colorIndex,
      colorStartIndex: colorStartIndex,
      reservedCategoryAccents: reservedCategoryAccents,
    );

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
                  const SizedBox(height: 10),
                  const Icon(
                    Icons.arrow_forward,
                    color: AppPalette.ink,
                    size: 21,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationDetailDialog extends StatelessWidget {
  const _NotificationDetailDialog({required this.notification});

  final NotificationFeedItem notification;

  bool get _canOpenRoute =>
      notification.type != NotificationFeedType.warning &&
      notification.routeName != null &&
      notification.routeName!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final visuals = _NotificationVisuals.fromItem(
      notification,
      colorIndex: 0,
      colorStartIndex: 0,
      reservedCategoryAccents: const <String, ExpenseAccentVisual>{},
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: CircleAvatar(
                radius: 26,
                backgroundColor: visuals.iconBackgroundColor,
                child: visuals.iconAssetPath != null
                    ? SvgPicture.asset(
                        visuals.iconAssetPath!,
                        width: 24,
                        height: 24,
                      )
                    : Icon(visuals.icon, color: AppPalette.ink, size: 24),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              notification.detailTitle,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppPalette.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _dialogTimestamp(notification.createdAt),
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.fieldHint.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              notification.detailMessage,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppPalette.fieldHint,
                height: 1.28,
              ),
            ),
            if (notification.amount != null) ...[
              const SizedBox(height: 14),
              Text(
                NotificationFeedService.formatAmount(notification.amount!),
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_canOpenRoute) ...[
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await AppNavigationService.openRedirect(
                        AppRedirect(
                          routeName: notification.routeName!,
                          routeArgumentInt: notification.routeArgumentInt,
                        ),
                      );
                    },
                    child: Text(
                      'Open',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Close',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.fieldHint,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dialogTimestamp(DateTime value) {
    return DateFormat('MMM d, y h:mm a', 'en_US').format(value);
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
              'Automatic alerts about goals, budgets, imports, and spending patterns will appear here.',
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
      case NotificationFeedType.warning:
        return _NotificationVisuals(
          backgroundColor: accentVisual.backgroundColor,
          iconBackgroundColor: accentVisual.accentColor,
          icon: Icons.warning_amber_rounded,
          iconAssetPath: item.category == null
              ? null
              : ExpenseVisuals.iconAssetPathFor(item.category!),
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
