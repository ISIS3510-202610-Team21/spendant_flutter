import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app.dart';
import '../theme/spendant_theme.dart';

enum SpendAntNavItem { profile, home, add, goals, cards }

class SpendAntBottomNav extends StatelessWidget {
  const SpendAntBottomNav({
    super.key,
    required this.currentItem,
    this.onProfileTap,
    this.onGoalsTap,
    this.onIncomeTap,
  });

  final SpendAntNavItem currentItem;
  final VoidCallback? onProfileTap;
  final VoidCallback? onGoalsTap;
  final VoidCallback? onIncomeTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    const barHeight = 42.0;
    const addButtonSize = 56.0;
    const overlapHeight = addButtonSize / 2;

    return SizedBox(
      height: overlapHeight + barHeight + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: barHeight + bottomInset,
              color: AppPalette.green,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavIconButton(
                    assetPath: 'web/icons/Profile.svg',
                    selected: currentItem == SpendAntNavItem.profile,
                    onTap: () {
                      if (onProfileTap != null) {
                        onProfileTap!();
                        return;
                      }
                      if (currentItem != SpendAntNavItem.profile) {
                        Navigator.of(context).pushReplacementNamed(
                          AppRoutes.setGoal,
                          arguments: 0,
                        );
                      }
                    },
                  ),
                  _NavIconButton(
                    assetPath: 'web/icons/Home.svg',
                    selected: currentItem == SpendAntNavItem.home,
                    onTap: () {
                      if (currentItem != SpendAntNavItem.home) {
                        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
                      }
                    },
                  ),
                  const SizedBox(width: addButtonSize),
                  _NavIconButton(
                    assetPath: 'web/icons/Goals.svg',
                    selected: currentItem == SpendAntNavItem.goals,
                    onTap: () {
                      if (onGoalsTap != null) {
                        onGoalsTap!();
                        return;
                      }
                      if (currentItem != SpendAntNavItem.goals) {
                        Navigator.of(context).pushReplacementNamed(
                          AppRoutes.setGoal,
                          arguments: 1,
                        );
                      }
                    },
                  ),
                  _NavIconButton(
                    assetPath: 'web/icons/Income.svg',
                    selected: currentItem == SpendAntNavItem.cards,
                    onTap: () {
                      if (onIncomeTap != null) {
                        onIncomeTap!();
                        return;
                      }
                      if (currentItem != SpendAntNavItem.cards) {
                        Navigator.of(context).pushReplacementNamed(AppRoutes.budget);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: InkWell(
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.newExpense),
              borderRadius: AppRadius.pill,
              child: Container(
                width: addButtonSize,
                height: addButtonSize,
                decoration: const BoxDecoration(
                  color: AppPalette.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: AppPalette.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.assetPath,
    required this.selected,
    required this.onTap,
  });

  final String assetPath;
  final bool selected;
  final VoidCallback onTap;

  static const _selectedDecoration = BoxDecoration(
    color: Color(0xFF41B864),
    borderRadius: AppRadius.chip,
    boxShadow: [BoxShadow(color: Color(0xFF41B864), blurRadius: 0, spreadRadius: 2)],
  );

  static const _unselectedDecoration = BoxDecoration(
    color: Colors.transparent,
    borderRadius: AppRadius.chip,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 38,
      height: 28,
      decoration: selected ? _selectedDecoration : _unselectedDecoration,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: SvgPicture.asset(
          assetPath,
          width: 20,
          height: 20,
        ),
      ),
    );
  }
}
