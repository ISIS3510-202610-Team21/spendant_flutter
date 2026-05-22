import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'exchange_rate_db_service.dart';

/// Global state for the active visual currency.
///
/// PERSISTENCE RULE
/// ----------------
/// Firebase and Hive always store raw COP amounts.  This provider is a
/// purely visual/client-side overlay: it converts COP → [activeCurrency]
/// for display only.  No remote data is ever mutated.
///
/// USAGE
/// -----
/// ```dart
/// // Read anywhere:
/// final local = CurrencyProvider.instance.convertToLocal(amountInCOP);
/// final display = CurrencyProvider.instance.formatFromCOP(amountInCOP);
///
/// // React to changes:
/// ListenableBuilder(
///   listenable: CurrencyProvider.instance,
///   builder: (context, _) => Text(CurrencyProvider.instance.formatFromCOP(amount)),
/// )
/// ```
class CurrencyProvider extends ChangeNotifier {
  CurrencyProvider._();

  static final CurrencyProvider instance = CurrencyProvider._();

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Currently selected ISO currency code shown in the UI.
  String _activeCurrency = 'COP';

  /// Rate: 1 COP = [_activeRate] units of [_activeCurrency].
  double _activeRate = 1.0;

  /// Full cache loaded from SQLite — ISO code → COP-indexed rate.
  Map<String, double> _ratesCache = {'COP': 1.0};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  String get activeCurrency => _activeCurrency;
  double get activeRate => _activeRate;
  Map<String, double> get ratesCache => Map.unmodifiable(_ratesCache);

  /// Whether the active currency is the base (COP) — no conversion needed.
  bool get isBaseCurrency => _activeCurrency == 'COP';

  /// Converts a raw COP amount to the currently active local currency.
  double convertToLocal(double amountInCOP) => amountInCOP * _activeRate;

  /// Converts a local-currency amount back to COP.
  /// Converts [amountInLocal] to COP, rounded UP to the nearest integer.
  /// COP never uses decimals — rounding up avoids losing value precision.
  double convertToCOP(double amountInLocal) {
    if (_activeRate == 0) return 0;
    return (amountInLocal / _activeRate).ceilToDouble();
  }

  /// Formats [amountInCOP] with the active currency prefix.
  ///
  /// Examples:
  ///   COP active  →  "COP 150,000"
  ///   USD active  →  "USD 42.85"
  ///   JPY active  →  "JPY 6,300"
  String formatFromCOP(double amountInCOP) {
    final converted = convertToLocal(amountInCOP);
    return '$_activeCurrency ${_formatValue(converted)}';
  }

  static const _kPrefKey = 'active_visual_currency';

  /// Selects [isoCode] as the active visual currency and persists the choice.
  ///
  /// [rate] is the COP-indexed rate (1 COP = [rate] units of [isoCode]).
  void setActiveCurrency(String isoCode, double rate) {
    if (_activeCurrency == isoCode) return;
    _activeCurrency = isoCode;
    _activeRate = rate;
    notifyListeners();
    // Persist asynchronously — never blocks the UI.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_kPrefKey, isoCode),
    );
  }

  /// Loads rates from the local SQLite cache into memory and optionally
  /// refreshes the active currency rate when its ISO code is already known.
  ///
  /// Call this once during app startup after [ExchangeRateDbService.init].
  Future<void> loadFromDb() async {
    try {
      // Restore rates from SQLite.
      final stored = await ExchangeRateDbService.getAllAsMap();
      if (stored.isNotEmpty) {
        _ratesCache = {
          for (final entry in stored.entries)
            entry.key: entry.value.rate,
        };
        _ratesCache['COP'] = 1.0;
      }

      // Restore persisted currency selection from SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final savedIso = prefs.getString(_kPrefKey);
      if (savedIso != null && _ratesCache.containsKey(savedIso)) {
        _activeCurrency = savedIso;
        _activeRate = _ratesCache[savedIso]!;
      } else if (_ratesCache.containsKey(_activeCurrency)) {
        // Rates just updated — refresh active rate for the current selection.
        _activeRate = _ratesCache[_activeCurrency]!;
      }

      notifyListeners();
    } catch (error) {
      debugPrint('CurrencyProvider.loadFromDb error: $error');
    }
  }

  /// Returns the stored rate for [isoCode], or 1.0 as a safe fallback.
  double rateFor(String isoCode) => _ratesCache[isoCode] ?? 1.0;

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  static final NumberFormat _intFormatter = NumberFormat('#,###', 'en_US');
  static final NumberFormat _decFormatter = NumberFormat('#,##0.00', 'en_US');

  String _formatValue(double value) {
    // Currencies like JPY, CLP, COP use whole numbers; others use 2 decimals.
    const wholeNumberCurrencies = {'COP', 'JPY', 'CLP', 'ARS'};
    if (wholeNumberCurrencies.contains(_activeCurrency)) {
      return _intFormatter.format(value.round());
    }
    return _decFormatter.format(value);
  }
}
