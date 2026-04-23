import 'package:flutter/material.dart';

import '../models/expense_model.dart';
import '../services/expense_moment_service.dart';

class ExpenseAccentVisual {
  const ExpenseAccentVisual({
    required this.accentColor,
    required this.backgroundColor,
  });

  final Color accentColor;
  final Color backgroundColor;
}

class ExpenseCategoryTotal {
  const ExpenseCategoryTotal({required this.label, required this.amount});

  final String label;
  final double amount;
}

abstract final class ExpenseVisuals {
  static const List<String> orderedLabels = <String>[
    'University Fees',
    'Learning Materials',
    'Commute',
    'Food',
    'Group Hangouts',
    'Food Delivery',
    'Entertainment',
    'Subscriptions',
    'Gifts',
    'Rent',
    'Utilities',
    'Services',
    'Groceries',
    'Personal Care',
    'Transport',
    'Owed',
    'Impulse',
    'Emergency',
  ];

  /// Maps every detail label to its primary category (Food / Transport / Services / Other).
  /// Single source of truth — used by auto-categorization, cloud sync, advice, and UI.
  static const Map<String, String> detailLabelPrimaryCategories =
      <String, String>{
        'Food': 'Food',
        'Food Delivery': 'Food',
        'Groceries': 'Food',
        'Commute': 'Transport',
        'Transport': 'Transport',
        'Learning Materials': 'Services',
        'University Fees': 'Services',
        'Personal Care': 'Services',
        'Rent': 'Services',
        'Services': 'Services',
        'Utilities': 'Services',
        'Entertainment': 'Other',
        'Gifts': 'Other',
        'Group Hangouts': 'Other',
        'Subscriptions': 'Other',
        'Emergency': 'Other',
        'Impulse': 'Other',
        'Owed': 'Other',
      };

  static const List<Color> reservedChartColors = <Color>[
    Color(0xFF297DE7),
    Color(0xFFFF632D),
    Color(0xFFFBBE2B),
    Color(0xFFFD8D8C),
  ];

  static const List<Color> rotatingColors = <Color>[
    Color(0xFF78E4B0),
    Color(0xFFB87DE9),
    Color(0xFF4AD3F5),
    Color(0xFFBDDD34),
    Color(0xFF9A1737),
    Color(0xFFFF886E),
    Color(0xFF245FC7),
    Color(0xFFA1BF9D),
    Color(0xFF5B204E),
    Color(0xFFD1A039),
  ];

  static List<String> resolveDisplayLabels(ExpenseModel expense) {
    return resolveDisplayLabelsFromValues(
      detailLabels: expense.detailLabels,
      primaryCategory: expense.primaryCategory,
    );
  }

  static String resolveDisplayLabel(
    ExpenseModel expense, {
    Iterable<String> prioritizedLabels = const <String>[],
  }) {
    return resolveDisplayLabelFromValues(
      detailLabels: expense.detailLabels,
      primaryCategory: expense.primaryCategory,
      prioritizedLabels: prioritizedLabels,
      stableSeed: Object.hash(
        expense.key,
        expense.createdAt.microsecondsSinceEpoch,
        expense.name,
        expense.amount.round(),
        expense.primaryCategory,
      ),
    );
  }

  static List<ExpenseCategoryTotal> topCategoryTotalsForMonth(
    Iterable<ExpenseModel> expenses, {
    DateTime? now,
    int limit = 4,
  }) {
    final reference = now ?? DateTime.now();
    final totals = <String, double>{};

    for (final expense in expenses) {
      if (expense.date.year != reference.year ||
          expense.date.month != reference.month ||
          ExpenseMomentService.isFutureExpense(expense, now: reference)) {
        continue;
      }

      for (final label in resolveDisplayLabels(expense)) {
        totals[label] = (totals[label] ?? 0) + expense.amount;
      }
    }

    final sortedEntries =
        totals.entries.where((entry) => entry.value > 0).toList()
          ..sort((left, right) {
            final amountComparison = right.value.compareTo(left.value);
            if (amountComparison != 0) {
              return amountComparison;
            }

            return orderIndexForLabel(
              left.key,
            ).compareTo(orderIndexForLabel(right.key));
          });

    return sortedEntries
        .take(limit)
        .map(
          (entry) =>
              ExpenseCategoryTotal(label: entry.key, amount: entry.value),
        )
        .toList();
  }

  static Map<String, ExpenseAccentVisual> reservedAccentsForMonth(
    Iterable<ExpenseModel> expenses, {
    DateTime? now,
    int limit = 4,
  }) {
    final topCategories = topCategoryTotalsForMonth(
      expenses,
      now: now,
      limit: limit,
    );
    final accents = <String, ExpenseAccentVisual>{};

    for (var index = 0; index < topCategories.length; index++) {
      accents[topCategories[index].label] = accentFromColor(
        reservedChartColors[index],
      );
    }

    return accents;
  }

  static List<String> resolveDisplayLabelsFromValues({
    required List<String> detailLabels,
    String? primaryCategory,
  }) {
    final labels = detailLabels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    if (labels.isNotEmpty) {
      final uniqueLabels = <String>[];
      final seenLabels = <String>{};

      for (final label in labels) {
        if (seenLabels.add(label)) {
          uniqueLabels.add(label);
        }
      }

      return uniqueLabels;
    }

    return <String>[_fallbackLabelForPrimaryCategory(primaryCategory)];
  }

  static String resolveDisplayLabelFromValues({
    required List<String> detailLabels,
    String? primaryCategory,
    Iterable<String> prioritizedLabels = const <String>[],
    int? stableSeed,
  }) {
    final labels = resolveDisplayLabelsFromValues(
      detailLabels: detailLabels,
      primaryCategory: primaryCategory,
    );

    for (final prioritizedLabel in prioritizedLabels) {
      if (labels.contains(prioritizedLabel)) {
        return prioritizedLabel;
      }
    }

    if (labels.length == 1) {
      return labels.first;
    }

    final seed = stableSeed ?? Object.hashAll(labels);
    final index = (seed & 0x7fffffff) % labels.length;
    return labels[index];
  }

  static String _fallbackLabelForPrimaryCategory(String? primaryCategory) {
    switch (primaryCategory?.trim()) {
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

  static int orderIndexForLabel(String label) {
    final index = orderedLabels.indexOf(label.trim());
    return index == -1 ? orderedLabels.length : index;
  }

  static String iconAssetPathFor(String label) {
    switch (label.trim()) {
      case 'University Fees':
        return 'web/icons/UniversityFees.svg';
      case 'Learning Materials':
        return 'web/icons/LearningMaterials.svg';
      case 'Commute':
        return 'web/icons/Commute.svg';
      case 'Food':
        return 'web/icons/Food.svg';
      case 'Group Hangouts':
        return 'web/icons/GroupHangouts.svg';
      case 'Food Delivery':
        return 'web/icons/FoodDelivery.svg';
      case 'Entertainment':
        return 'web/icons/Entertaiment.svg';
      case 'Subscriptions':
        return 'web/icons/Subscriptions.svg';
      case 'Gifts':
        return 'web/icons/Gifts.svg';
      case 'Rent':
        return 'web/icons/Rent.svg';
      case 'Utilities':
        return 'web/icons/Utilities.svg';
      case 'Services':
        return 'web/icons/Services.svg';
      case 'Groceries':
        return 'web/icons/Groceries.svg';
      case 'Personal Care':
        return 'web/icons/PersonalCare.svg';
      case 'Transport':
        return 'web/icons/Transport.svg';
      case 'Owed':
        return 'web/icons/Owed.svg';
      case 'Impulse':
        return 'web/icons/Impulse.svg';
      case 'Emergency':
        return 'web/icons/Emergency.svg';
      default:
        return 'web/icons/Gifts.svg';
    }
  }

  static ExpenseAccentVisual rotatingAccent({
    required int itemIndex,
    required int startIndex,
  }) {
    final paletteIndex = (startIndex + itemIndex) % rotatingColors.length;
    return accentFromColor(rotatingColors[paletteIndex]);
  }

  static ExpenseAccentVisual accentFromColor(Color accentColor) {
    return ExpenseAccentVisual(
      accentColor: accentColor,
      backgroundColor: Color.lerp(accentColor, Colors.white, 0.76)!,
    );
  }
}
