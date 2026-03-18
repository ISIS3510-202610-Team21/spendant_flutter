import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/expense_draft.dart';
import '../services/notifications_store.dart';
import '../theme/spendant_theme.dart';
import 'new_expense_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static final List<_NotificationSection> _sections = <_NotificationSection>[
    _NotificationSection(
      title: 'Today',
      items: <_NotificationItem>[
        _NotificationItem.expense(
          timeLabel: '5 minutes ago',
          title: 'Chick & Chips Lunch',
          subtitle: 'Food',
          amountLabel: 'COP 23,000',
          backgroundColor: const Color(0xFFCFE2FF),
          iconBackgroundColor: AppPalette.food,
          iconAssetPath: 'web/icons/Food.svg',
          draft: ExpenseDraft(
            name: 'Chick & Chips Lunch',
            amount: '23,000',
            primaryCategory: 'Food',
            detailLabels: <String>['Social/Group Hangouts'],
            date: DateTime(2026, 3, 17),
            time: TimeOfDay(hour: 12, minute: 35),
            locationLabel: 'Campus Food Court',
          ),
        ),
        _NotificationItem.expense(
          timeLabel: '5 minutes ago',
          title: 'TM to University',
          subtitle: 'Transport',
          amountLabel: 'COP 23,000',
          backgroundColor: const Color(0xFFF6D1C4),
          iconBackgroundColor: AppPalette.transport,
          iconAssetPath: 'web/icons/Transport.svg',
          draft: ExpenseDraft(
            name: 'TM to University',
            amount: '23,000',
            primaryCategory: 'Transport',
            detailLabels: <String>['Commute'],
            date: DateTime(2026, 3, 17),
            time: TimeOfDay(hour: 7, minute: 50),
            locationLabel: 'TransMilenio station',
          ),
        ),
        _NotificationItem.warning(
          timeLabel: '15 minutes ago',
          title: 'New Warning!',
          backgroundColor: const Color(0xFFCFF7D8),
        ),
      ],
    ),
    _NotificationSection(
      title: 'Yesterday',
      items: <_NotificationItem>[
        _NotificationItem.goal(
          timeLabel: 'Yesterday, 18:05',
          title: 'Goal Achieved!',
          backgroundColor: const Color(0xFFCFF7D8),
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    NotificationsStore.markNotificationsAsViewed();
  }

  Future<void> _openExpenseEditor(ExpenseDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewExpenseScreen(
          headerTitle: 'Edit Expense',
          initialDraft: draft,
        ),
      ),
    );
  }

  Future<void> _openNotificationDetail(_NotificationType type) async {
    switch (type) {
      case _NotificationType.expense:
        return;
      case _NotificationType.warning:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const _WarningDetailScreen()),
        );
        return;
      case _NotificationType.goal:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const _GoalAchievedDetailScreen(),
          ),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _NotificationsHeader(onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                children: [
                  for (final section in _sections) ...[
                    Text(
                      section.title,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.ink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final item in section.items) ...[
                      _NotificationCard(
                        item: item,
                        onTap: () {
                          if (item.type == _NotificationType.expense &&
                              item.draft != null) {
                            _openExpenseEditor(item.draft!);
                            return;
                          }

                          _openNotificationDetail(item.type);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.green,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
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
  const _NotificationCard({required this.item, required this.onTap});

  final _NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showsActionIcon = item.type == _NotificationType.expense;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: item.backgroundColor,
            borderRadius: BorderRadius.circular(2),
            border: const Border(
              bottom: BorderSide(color: Color(0xFFD0D0D0), width: 2),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: item.iconBackgroundColor,
                child: item.iconAssetPath != null
                    ? SvgPicture.asset(
                        item.iconAssetPath!,
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(
                          AppPalette.ink,
                          BlendMode.srcIn,
                        ),
                      )
                    : Icon(item.icon, color: AppPalette.ink, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.timeLabel,
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
              const SizedBox(width: 8),
              if (item.amountLabel != null) ...[
                Text(
                  item.amountLabel!,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Icon(
                showsActionIcon ? Icons.edit_outlined : Icons.arrow_forward,
                color: AppPalette.ink,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningDetailScreen extends StatelessWidget {
  const _WarningDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _NotificationDetailShell(
      backgroundColor: const Color(0xFFFF632D),
      assetPath: 'web/ant/Surprised.svg',
      title: '"Hey! Everything alright\nover there?"',
      body:
          'We noticed some unusual activity in Transport. Before your future self gets the wrong idea, was this purchase planned or is it a midterm stress treat? Think about it for two minutes.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE5DD),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: AppPalette.transport,
              child: Icon(Icons.train_outlined, color: AppPalette.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uber',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.ink,
                    ),
                  ),
                  Text(
                    'Transport',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'COP 51,500',
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

class _GoalAchievedDetailScreen extends StatelessWidget {
  const _GoalAchievedDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _NotificationDetailShell(
      backgroundColor: const Color(0xFF3C80E6),
      assetPath: 'web/ant/Presenting.svg',
      title: 'Lvl. Up! Goal\nAccomplished!',
      body:
          "Look at you. You just smashed your goal: \$660,000 for FEP. Your future self is already doing a happy dance. Treat yourself to something small. You've earned the bragging rights.",
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
                    SvgPicture.asset(assetPath, height: 240, fit: BoxFit.contain),
                    if (child != null) ...[
                      const SizedBox(height: 22),
                      child!,
                    ],
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

enum _NotificationType { expense, warning, goal }

class _NotificationSection {
  const _NotificationSection({required this.title, required this.items});

  final String title;
  final List<_NotificationItem> items;
}

class _NotificationItem {
  const _NotificationItem({
    required this.type,
    required this.timeLabel,
    required this.title,
    required this.backgroundColor,
    required this.iconBackgroundColor,
    required this.icon,
    this.subtitle,
    this.amountLabel,
    this.iconAssetPath,
    this.draft,
  });

  _NotificationItem.expense({
    required String timeLabel,
    required String title,
    required String subtitle,
    required String amountLabel,
    required Color backgroundColor,
    required Color iconBackgroundColor,
    required String iconAssetPath,
    required ExpenseDraft draft,
  }) : this(
         type: _NotificationType.expense,
         timeLabel: timeLabel,
         title: title,
         subtitle: subtitle,
         amountLabel: amountLabel,
         backgroundColor: backgroundColor,
         iconBackgroundColor: iconBackgroundColor,
         icon: Icons.edit_outlined,
         iconAssetPath: iconAssetPath,
         draft: draft,
       );

  _NotificationItem.warning({
    required String timeLabel,
    required String title,
    required Color backgroundColor,
  }) : this(
         type: _NotificationType.warning,
         timeLabel: timeLabel,
         title: title,
         backgroundColor: backgroundColor,
         iconBackgroundColor: const Color(0xFF5AD070),
         icon: Icons.warning_amber_rounded,
       );

  _NotificationItem.goal({
    required String timeLabel,
    required String title,
    required Color backgroundColor,
  }) : this(
         type: _NotificationType.goal,
         timeLabel: timeLabel,
         title: title,
         backgroundColor: backgroundColor,
         iconBackgroundColor: const Color(0xFF5AD070),
         icon: Icons.flag_outlined,
       );

  final _NotificationType type;
  final String timeLabel;
  final String title;
  final String? subtitle;
  final String? amountLabel;
  final Color backgroundColor;
  final Color iconBackgroundColor;
  final IconData icon;
  final String? iconAssetPath;
  final ExpenseDraft? draft;
}
