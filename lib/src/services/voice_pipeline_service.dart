import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter/services.dart';

import '../models/voice_parse_result.dart';
import '../services/currency_provider.dart';
import '../services/voice_pattern_cache_service.dart';

// ---------------------------------------------------------------------------
// Pipeline overview
// ---------------------------------------------------------------------------
//
//  Stage 1 (Audio Capture) ──► Stage 2 (STT Transcription)
//      └─ Both handled by Android SpeechRecognizer via MethodChannel.
//         The OS runs these in its own background service — the Dart/UI
//         thread is never blocked.
//
//  Stage 3 (Entity Parsing) ──► Isolate.run(_parseEntities)
//      └─ Pure Dart computation; regex extraction runs in a fresh isolate
//         so the widget tree never jank during analysis.
//
//  Cache layer (Hash-Phrase):
//      Before Stage 3 runs, VoicePatternCacheService.lookup() is called.
//      A cache hit bypasses Isolate 3 entirely and returns instantly.
// ---------------------------------------------------------------------------

abstract final class VoicePipelineService {
  static const _channel = MethodChannel('spendant_flutter/speech');

  // ---------------------------------------------------------------------------
  // Stage 1 + 2 — Android STT via MethodChannel
  // ---------------------------------------------------------------------------

  /// Starts the native Android SpeechRecognizer.
  ///
  /// Returns the raw transcription string when the user finishes speaking,
  /// or null if recognition failed / was cancelled.
  /// This call blocks until Android fires onResults/onError — UI stays
  /// responsive because the platform side runs in its own service thread.
  static Future<String?> startListening() async {
    if (kIsWeb) return null;
    try {
      final result = await _channel.invokeMethod<String>('startListening');
      return result;
    } on PlatformException catch (e) {
      debugPrint('VoicePipeline Stage 1+2 error: ${e.message}');
      return null;
    }
  }

  /// Signals the native recognizer to stop early and flush pending audio.
  static Future<void> stopListening() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('stopListening');
    } on PlatformException catch (e) {
      debugPrint('VoicePipeline stopListening error: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Stage 3 — Entity Parsing (Isolate.run)
  // ---------------------------------------------------------------------------

  /// Parses [rawText] into a [VoiceParseResult].
  ///
  /// Pipeline:
  ///   1. Check [VoicePatternCacheService] — cache hit → return instantly.
  ///   2. Cache miss → [Isolate.run] with [_parseEntities] → run regex
  ///      extraction on a background isolate.
  ///   3. Currency conversion applied on main isolate via [CurrencyProvider].
  ///   4. Persist result in cache for future requests.
  static Future<VoiceParseResult?> parseAndCache(String rawText) async {
    // ── Cache lookup (bypasses Isolate 3 on hit) ───────────────────────────
    final cached = await VoicePatternCacheService.lookup(rawText);
    if (cached != null) {
      debugPrint('VoicePipeline: cache hit for "${rawText.substring(0, rawText.length.clamp(0, 30))}…"');
      return cached;
    }

    // ── Stage 3: background isolate entity parsing ─────────────────────────
    final partial = await Isolate.run(() => _parseEntities(rawText));
    if (partial == null) return null;

    // ── Currency conversion on main isolate (needs CurrencyProvider) ───────
    final ratesCopy = Map<String, double>.from(
      CurrencyProvider.instance.ratesCache,
    );
    final convertedCop = _convertToCop(
      partial.originalAmount,
      partial.originalCurrency,
      ratesCopy,
    );

    final result = VoiceParseResult(
      rawText: partial.rawText,
      productName: partial.productName,
      originalAmount: partial.originalAmount,
      originalCurrency: partial.originalCurrency,
      convertedAmountCop: convertedCop,
      date: partial.date,
      time: partial.time,
      location: partial.location,
    );

    // ── Persist in cache ───────────────────────────────────────────────────
    await VoicePatternCacheService.store(rawText, result);

    return result;
  }

  // ---------------------------------------------------------------------------
  // Private — currency conversion (main isolate, needs rates map)
  // ---------------------------------------------------------------------------

  static double _convertToCop(
    double amount,
    String iso,
    Map<String, double> rates,
  ) {
    if (iso == 'COP') return amount;
    final rate = rates[iso.toUpperCase()];
    if (rate == null || rate == 0) return amount;
    // rate = "1 COP expressed in iso" → 1 iso = 1/rate COP
    return amount / rate;
  }
}

// ---------------------------------------------------------------------------
// Top-level function — MUST be top-level for Isolate.run()
// ---------------------------------------------------------------------------

/// Entity extraction logic.  Runs inside a fresh [Isolate] via
/// [Isolate.run].  No platform channels, no Flutter bindings.
///
/// Currency conversion is intentionally left to the main isolate
/// ([VoicePipelineService.parseAndCache]) because it needs [CurrencyProvider].
/// This function returns amounts in the dictated currency unit.
_PartialParseResult? _parseEntities(String raw) {
  if (raw.trim().isEmpty) return null;

  final text = raw.toLowerCase().trim();

  // ── Amount extraction ────────────────────────────────────────────────────
  // Matches: "15 dollars", "25,000 pesos", "5.99 euros", "45k", "fifteen"
  final amountRegex = RegExp(
    r'(?:i paid\s+|paid\s+)?'
    r'((?:\d{1,3}(?:[,.\s]\d{3})*|\d+)(?:[,.]\d{1,2})?|\d+(?:\.\d+)?)\s*'
    r'(?:thousand|k\b)?',
    caseSensitive: false,
  );

  double? amount;
  String? amountRaw;
  final amountMatch = amountRegex.firstMatch(text);
  if (amountMatch != null) {
    amountRaw = amountMatch.group(1);
    if (amountRaw != null) {
      final cleaned = amountRaw
          .replaceAll(RegExp(r'[\s,](?=\d{3})'), '') // remove thousands sep
          .replaceAll(',', '.');
      amount = double.tryParse(cleaned);
      // Handle "k" suffix
      if (text.contains(RegExp(r'\d\s*k\b'))) {
        amount = (amount ?? 0) * 1000;
      }
    }
  }

  if (amount == null || amount <= 0) return null;

  // ── Currency extraction ──────────────────────────────────────────────────
  final currencyMap = {
    r'dollar[s]?|usd': 'USD',
    r'euro[s]?|eur': 'EUR',
    r'peso[s]?|cop': 'COP',
    r'pound[s]?|sterling|gbp': 'GBP',
    r'yen[s]?|jpy': 'JPY',
    r'real[is]?|reais|brl': 'BRL',
    r'cad|canadian': 'CAD',
    r'aud|australian': 'AUD',
    r'chf|franc[s]?': 'CHF',
    r'mxn|mexican': 'MXN',
    r'cny|yuan': 'CNY',
    r'clp|chilean': 'CLP',
    r'pen|sol[es]?': 'PEN',
    r'ars|argentine': 'ARS',
  };

  String detectedCurrency = 'COP'; // default
  for (final entry in currencyMap.entries) {
    if (RegExp(entry.key, caseSensitive: false).hasMatch(text)) {
      detectedCurrency = entry.value;
      break;
    }
  }

  // ── Product extraction ───────────────────────────────────────────────────
  // Text between "for" and any of: (on|at|yesterday|today|tomorrow|end)
  final productRegex = RegExp(
    r'\bfor\s+([a-z0-9 ]+?)(?:\s+(?:on|at|yesterday|today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|$)',
    caseSensitive: false,
  );
  final productMatch = productRegex.firstMatch(text);
  final product = productMatch != null
      ? _capitalize(productMatch.group(1)?.trim() ?? '')
      : _capitalize(_fallbackProduct(text));

  // ── Date extraction ──────────────────────────────────────────────────────
  final now = DateTime.now();
  DateTime date = now;

  if (text.contains('yesterday')) {
    date = now.subtract(const Duration(days: 1));
  } else if (text.contains('tomorrow')) {
    date = now.add(const Duration(days: 1));
  } else if (text.contains('today')) {
    date = now;
  } else {
    // Match day names
    const weekdays = {
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    for (final entry in weekdays.entries) {
      if (text.contains(entry.key)) {
        int diff = now.weekday - entry.value;
        if (diff <= 0) diff += 7;
        date = now.subtract(Duration(days: diff));
        break;
      }
    }
  }

  // ── Time extraction ──────────────────────────────────────────────────────
  String? time;
  final timeRegex = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
    caseSensitive: false,
  );
  final timeMatch = timeRegex.firstMatch(text);
  if (timeMatch != null) {
    int hour = int.parse(timeMatch.group(1)!);
    final min = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
    final ampm = timeMatch.group(3)!.toLowerCase();
    if (ampm == 'pm' && hour < 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;
    time = '${hour.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  // ── Location extraction ──────────────────────────────────────────────────
  // "at [location]" when it comes after time markers, or at end after product
  String? location;
  final locationRegex = RegExp(
    r'(?:at the|at)\s+([a-z0-9 ]+?)(?:\s+(?:on|at \d)|$)',
    caseSensitive: false,
  );
  // Find last "at X" that isn't a time indicator
  final locationMatches = locationRegex.allMatches(text).toList();
  for (final m in locationMatches.reversed) {
    final candidate = m.group(1)?.trim() ?? '';
    // Skip if it looks like a time expression
    if (!RegExp(r'^\d{1,2}').hasMatch(candidate) &&
        !['home', 'work', 'school', 'am', 'pm'].contains(candidate)) {
      location = _capitalize(candidate);
      break;
    }
  }

  return _PartialParseResult(
    rawText: raw,
    productName: product.isEmpty ? 'Expense' : product,
    originalAmount: amount,
    originalCurrency: detectedCurrency,
    date: DateUtils.dateOnly(date),
    time: time,
    location: location,
  );
}

// ---------------------------------------------------------------------------
// Private helpers (must be top-level for isolate use)
// ---------------------------------------------------------------------------

class _PartialParseResult {
  const _PartialParseResult({
    required this.rawText,
    required this.productName,
    required this.originalAmount,
    required this.originalCurrency,
    required this.date,
    this.time,
    this.location,
  });

  final String rawText;
  final String productName;
  final double originalAmount;
  final String originalCurrency;
  final DateTime date;
  final String? time;
  final String? location;
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

String _fallbackProduct(String text) {
  // Strip known prefixes and return a best-guess product name
  return text
      .replaceAll(RegExp(r'^i paid\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'^\d[\d,.k\s]*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b(dollar|euro|peso|pound|yen|usd|eur|cop|gbp|jpy)\w*\b', caseSensitive: false), '')
      .trim()
      .split(RegExp(r'\s+'))
      .take(4)
      .join(' ');
}
