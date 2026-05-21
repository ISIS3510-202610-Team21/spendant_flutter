import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'exchange_rate_db_service.dart';

/// Manages background synchronization of exchange rates from an external API.
///
/// CACHING STRATEGY — Strict Weekly TTL (Anti-Rate-Limit)
/// -------------------------------------------------------
/// The sync never runs simply because the app is opened.  It follows a
/// strictly passive Lazy Fetch policy controlled by this decision tree:
///
///   1. If [exchange_rates] table is EMPTY → fetch immediately (first install).
///   2. Else if rates are >7 days old OR today is Saturday and last fetch
///      was a different Saturday → fetch.
///   3. Otherwise → terminate silently and use local storage.
///
/// THREADING
/// ---------
/// The HTTP fetch + JSON parsing runs inside a background [Isolate] via
/// [Isolate.run], keeping both the UI thread and the platform-channel thread
/// free.  SQLite reads/writes happen on the Dart event loop (async/await)
/// which is already non-blocking for the UI.
abstract final class ExchangeRateSyncService {
  /// Builds the API URL from the key stored in .env.
  /// Format: https://v6.exchangerate-api.com/v6/{KEY}/latest/COP
  static String get _apiUrl {
    final key = dotenv.maybeGet('EXCHANGE_RATE_API_KEY') ?? '';
    return 'https://v6.exchangerate-api.com/v6/$key/latest/COP';
  }

  /// Entry point.  Must be called with [unawaited] on app launch so it never
  /// blocks navigation or the main rendering thread.
  static Future<void> runOnAppLaunch() async {
    if (kIsWeb) return;

    try {
      await ExchangeRateDbService.init();

      // ── Decision tree ──────────────────────────────────────────────────────
      final empty = await ExchangeRateDbService.isEmpty();
      if (empty) {
        // Case 1: First install → immediate background fetch.
        debugPrint('ExchangeRateSync: table empty — fetching initial rates.');
        await _triggerExternalFetch();
        return;
      }

      final lastFetch = await ExchangeRateDbService.latestFetchTime();
      if (lastFetch == null) {
        await _triggerExternalFetch();
        return;
      }

      final now = DateTime.now();
      final daysSinceLastFetch = now.difference(lastFetch).inDays;

      final requiresUpdate =
          (daysSinceLastFetch >= 7) ||
          (now.weekday == DateTime.saturday &&
              lastFetch.weekday != DateTime.saturday);

      if (requiresUpdate) {
        // Case 2: Meets obsolescence condition or new Saturday.
        debugPrint(
          'ExchangeRateSync: stale ($daysSinceLastFetch days) — refreshing.',
        );
        await _triggerExternalFetch();
      } else {
        // Case 3: Fresh cache — terminate immediately.
        debugPrint(
          'ExchangeRateSync: cache fresh ($daysSinceLastFetch days) — skipping fetch.',
        );
      }
      // ──────────────────────────────────────────────────────────────────────
    } catch (error) {
      // Never propagate — sync is best-effort and must not crash the app.
      debugPrint('ExchangeRateSync.runOnAppLaunch error: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Spawns a background isolate to fetch + parse the API response, then
  /// writes the results back to SQLite on the main isolate.
  static Future<void> _triggerExternalFetch() async {
    try {
      // Capture the URL on the main isolate (dotenv uses platform channels).
      // Pass it as a plain String into Isolate.run — no platform objects cross.
      final url = _apiUrl;
      // [Isolate.run] handles the CPU-bound network + JSON work off the main
      // thread.  The closure captures only primitive values (the URL string),
      // so it is safe to send to a fresh isolate.
      final rates = await Isolate.run(
        () => _fetchAndParseRates(url),
      );

      if (rates.isEmpty) {
        debugPrint('ExchangeRateSync: API returned empty rates map — skipping write.');
        return;
      }

      await ExchangeRateDbService.upsertRates(rates);
      debugPrint(
        'ExchangeRateSync: persisted ${rates.length} rates to local DB.',
      );
    } catch (error) {
      debugPrint('ExchangeRateSync._triggerExternalFetch error: $error');
    }
  }

  /// Runs inside a background [Isolate].  No platform channels allowed here.
  ///
  /// Returns a map of ISO code → COP-indexed rate.
  /// Returns an empty map on any failure so the caller can handle gracefully.
  static Future<Map<String, double>> _fetchAndParseRates(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != 200) {
        return {};
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final result = decoded['result'] as String?;
      if (result != 'success') return {};

      // exchangerate-api.com v6 uses "conversion_rates" as the key.
      final rawRates = decoded['conversion_rates'] as Map<String, dynamic>?;
      if (rawRates == null) return {};

      return rawRates.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } catch (_) {
      return {};
    }
  }
}
