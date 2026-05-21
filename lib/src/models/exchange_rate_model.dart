/// Represents a single row in the local [exchange_rates] SQLite table.
///
/// All rates are indexed relative to COP:
///   rate = 1 COP expressed in [currency]
///   e.g. currency='USD', rate=0.000263  →  1 COP = 0.000263 USD
class ExchangeRate {
  const ExchangeRate({
    required this.currency,
    required this.rate,
    required this.fetchedAt,
  });

  /// ISO 4217 currency code, e.g. 'USD', 'EUR', 'COP'.
  final String currency;

  /// How many units of [currency] equals 1 COP.
  final double rate;

  /// Timestamp when this rate was last fetched from the external API.
  final DateTime fetchedAt;

  factory ExchangeRate.fromRow(Map<String, Object?> row) {
    return ExchangeRate(
      currency: row['currency'] as String,
      rate: row['rate'] as double,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
    );
  }

  Map<String, Object?> toRow() => {
    'currency': currency,
    'rate': rate,
    'fetched_at': fetchedAt.millisecondsSinceEpoch,
  };
}
