import 'package:flutter/material.dart';

import '../../app.dart';
import '../theme/spendant_theme.dart';

enum SpendAntNavItem { profile, home, add, goals, cards }

class SpendAntBottomNav extends StatelessWidget {
  const SpendAntBottomNav({super.key, required this.currentItem});

  final SpendAntNavItem currentItem;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 75,
      color: AppPalette.green,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavIconButton(
            icon: Icons.person_outline,
            selected: currentItem == SpendAntNavItem.profile,
            onTap: () {},
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
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.newExpense),
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
              if (currentItem != SpendAntNavItem.goals) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.setGoal);
              }
            },
          ),
          _NavIconButton(
            icon: Icons.credit_card_outlined,
            selected: currentItem == SpendAntNavItem.cards,
            onTap: () {},
          ),
        ],
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
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: AppPalette.ink, size: selected ? 30 : 28),
    );
  }
}
