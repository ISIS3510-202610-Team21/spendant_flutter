import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/spendant_theme.dart';
import '../widgets/spendant_bottom_nav.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _categoryStats = <_CategoryStat>[
    _CategoryStat(
      label: 'Food',
      amount: 320000,
      color: AppPalette.food,
      icon: Icons.restaurant_outlined,
    ),
    _CategoryStat(
      label: 'Transport',
      amount: 265000,
      color: AppPalette.transport,
      icon: Icons.directions_bus_outlined,
    ),
    _CategoryStat(
      label: 'Services',
      amount: 218000,
      color: AppPalette.services,
      icon: Icons.lightbulb_outline,
    ),
    _CategoryStat(
      label: 'Other',
      amount: 148000,
      color: AppPalette.other,
      icon: Icons.storefront_outlined,
    ),
  ];

  static const _expenseGroups = <_ExpenseDayGroup>[
    _ExpenseDayGroup(
      title: 'Today Expenses',
      entries: [
        _ExpenseEntry(
          name: 'Chick & Chips Lunch',
          category: 'Food',
          amount: 'COP 23,000',
          color: Color(0xFFCFE2FF),
          icon: Icons.restaurant_outlined,
          iconColor: AppPalette.food,
        ),
        _ExpenseEntry(
          name: 'TM To the University',
          category: 'Transport',
          amount: 'COP 3,500',
          color: Color(0xFFF6D1C4),
          icon: Icons.directions_bus_outlined,
          iconColor: AppPalette.transport,
        ),
      ],
    ),
    _ExpenseDayGroup(
      title: 'Yesterday Expenses',
      entries: [
        _ExpenseEntry(
          name: 'Google Drive Month',
          category: 'Services',
          amount: 'COP 3,500',
          color: Color(0xFFF7E5A8),
          icon: Icons.lightbulb_outline,
          iconColor: AppPalette.services,
        ),
        _ExpenseEntry(
          name: 'Chick & Chips Lunch',
          category: 'Food',
          amount: 'COP 23,000',
          color: Color(0xFFCFE2FF),
          icon: Icons.restaurant_outlined,
          iconColor: AppPalette.food,
        ),
      ],
    ),
    _ExpenseDayGroup(
      title: 'Monday Expenses',
      entries: [
        _ExpenseEntry(
          name: 'Laundry Pickup',
          category: 'Other',
          amount: 'COP 18,000',
          color: Color(0xFFFBC5C4),
          icon: Icons.storefront_outlined,
          iconColor: AppPalette.other,
        ),
        _ExpenseEntry(
          name: 'Campus Bus Card',
          category: 'Transport',
          amount: 'COP 12,000',
          color: Color(0xFFF6D1C4),
          icon: Icons.directions_bus_outlined,
          iconColor: AppPalette.transport,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppPalette.green,
            padding: const EdgeInsets.fromLTRB(16, 58, 16, 14),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.notifications_none_outlined,
                        color: AppPalette.ink,
                        size: 28,
                      ),
                      Positioned(
                        right: 1,
                        top: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppPalette.expenseRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
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
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              children: [
                Text(
                  'Your Budget for today',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\$25,500 ',
                        style: GoogleFonts.nunito(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.green,
                        ),
                      ),
                      TextSpan(
                        text: 'COP',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'This month you have expended',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\$750,000 ',
                        style: GoogleFonts.nunito(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.expenseRed,
                          decoration: TextDecoration.underline,
                          decorationColor: AppPalette.food,
                          decorationThickness: 3,
                        ),
                      ),
                      TextSpan(
                        text: 'COP',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 170,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 12.0;
                      final width = (constraints.maxWidth - (gap * 3)) / 4;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final stat in _categoryStats)
                            SizedBox(
                              width: width,
                              child: _CategoryBarCard(stat: stat),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                for (final group in _expenseGroups) ...[
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
            ),
          ),
          const SpendAntBottomNav(currentItem: SpendAntNavItem.home),
        ],
      ),
    );
  }
}

class _CategoryBarCard extends StatelessWidget {
  const _CategoryBarCard({required this.stat});

  final _CategoryStat stat;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: 128,
        decoration: BoxDecoration(
          color: stat.color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(stat.icon, color: AppPalette.ink, size: 24),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                stat.label,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.ink,
                ),
              ),
            ),
          ],
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
            radius: 16,
            backgroundColor: entry.iconColor,
            child: Icon(entry.icon, size: 18, color: AppPalette.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.category,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
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
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStat {
  const _CategoryStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amount;
  final Color color;
  final IconData icon;
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
    required this.icon,
    required this.iconColor,
  });

  final String name;
  final String category;
  final String amount;
  final Color color;
  final IconData icon;
  final Color iconColor;
}
