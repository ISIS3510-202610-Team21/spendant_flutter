import 'dart:convert';

/// Result produced by the voice pipeline after passing through all 3 stages:
///   Stage 1+2 (Android SpeechRecognizer) → Stage 3 (Isolate entity parser).
///
/// [originalAmount] and [originalCurrency] preserve the user's dictated
/// values; [convertedAmountCop] is the COP equivalent computed by
/// [CurrencyProvider] after parsing (Firebase always stores COP).
class VoiceParseResult {
  const VoiceParseResult({
    required this.rawText,
    required this.productName,
    required this.originalAmount,
    required this.originalCurrency,
    required this.convertedAmountCop,
    required this.date,
    this.time,
    this.location,
  });

  final String rawText;
  final String productName;
  final double originalAmount;
  final String originalCurrency;
  final double convertedAmountCop;
  final DateTime date;
  final String? time;      // "HH:mm" 24-hour or null
  final String? location;  // free-text location name or null

  Map<String, dynamic> toJson() => {
    'rawText': rawText,
    'productName': productName,
    'originalAmount': originalAmount,
    'originalCurrency': originalCurrency,
    'convertedAmountCop': convertedAmountCop,
    'date': date.toIso8601String(),
    'time': time,
    'location': location,
  };

  factory VoiceParseResult.fromJson(Map<String, dynamic> json) {
    return VoiceParseResult(
      rawText: json['rawText'] as String,
      productName: json['productName'] as String,
      originalAmount: (json['originalAmount'] as num).toDouble(),
      originalCurrency: json['originalCurrency'] as String,
      convertedAmountCop: (json['convertedAmountCop'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String?,
      location: json['location'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  static VoiceParseResult fromJsonString(String s) =>
      VoiceParseResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
