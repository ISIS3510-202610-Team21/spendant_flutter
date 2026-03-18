import 'package:flutter/material.dart';

class ExpenseDraft {
  const ExpenseDraft({
    required this.name,
    required this.amount,
    required this.date,
    required this.time,
    this.primaryCategory,
    this.detailLabels = const <String>[],
    this.locationLabel,
    this.latitude,
    this.longitude,
  });

  final String name;
  final String amount;
  final String? primaryCategory;
  final List<String> detailLabels;
  final DateTime date;
  final TimeOfDay time;
  final String? locationLabel;
  final double? latitude;
  final double? longitude;
}
