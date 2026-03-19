import 'package:flutter/material.dart';

import '../../app.dart';
import '../theme/spendant_theme.dart';

enum SpendAntNavItem { profile, home, add, goals, cards }

class SpendAntBottomNav extends StatelessWidget {
  const SpendAntBottomNav({
    super.key,
    required this.currentItem,
    this.onProfileTap,
    this.onGoalsTap,
  });

  final SpendAntNavItem currentItem;
  final VoidCallback? onProfileTap;
  final VoidCallback? onGoalsTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      color: AppPalette.green,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 75,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavIconButton(
              icon: Icons.person_outline,
              selected: currentItem == SpendAntNavItem.profile,
              onTap: () {
                if (onProfileTap != null) {
                  onProfileTap!();
                  return;
                }
                if (currentItem != SpendAntNavItem.profile) {
                  Navigator.of(
                    context,
                  ).pushReplacementNamed(AppRoutes.setGoal, arguments: 0);
                }
              },
            ),
            _NavIconButton(
              icon: Icons.home_outlined,
              selected: currentItem == SpendAntNavItem.home,
              onTap: () {
                if (currentItem != SpendAntNavItem.home) {
                  Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                }
              },
            ),
            InkWell(
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.newExpense),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppPalette.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: AppPalette.white, size: 26),
              ),
            ),
            _NavIconButton(
              icon: Icons.flag_outlined,
              selected: currentItem == SpendAntNavItem.goals,
              onTap: () {
                if (onGoalsTap != null) {
                  onGoalsTap!();
                  return;
                }
                if (currentItem != SpendAntNavItem.goals) {
                  Navigator.of(
                    context,
                  ).pushReplacementNamed(AppRoutes.setGoal, arguments: 1);
                }
              },
            ),
            _NavIconButton(
              icon: Icons.credit_card_outlined,
              selected: currentItem == SpendAntNavItem.cards,
              onTap: () {
                if (currentItem != SpendAntNavItem.cards) {
                  Navigator.of(context).pushReplacementNamed(AppRoutes.budget);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 42,
      height: 34,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF41B864) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0xFF41B864),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 20,
        icon: Icon(icon, color: AppPalette.ink, size: selected ? 24 : 22),
      ),
    );
  }
}
