import 'package:intl/intl.dart';

/// Shared currency formatter for Colombian Peso (COP) amounts.
///
/// Using a single static instance avoids allocating a new [NumberFormat]
/// object on every call site, which is especially important inside
/// widget [build] methods and notification-generation loops.
abstract final class AppCurrencyFormatService {
  /// `#,###` formatter using `en_US` grouping conventions (comma thousands separator).
  static final NumberFormat currency = NumberFormat('#,###', 'en_US');

  /// Formats [amount] as a rounded COP string, e.g. `COP 1,200`.
  static String formatCOP(double amount) {
    return 'COP ${currency.format(amount.round())}';
  }

  /// Formats [amount] as a rounded plain string without the currency prefix.
  static String formatAmount(double amount) {
    return currency.format(amount.round());
  }
}
