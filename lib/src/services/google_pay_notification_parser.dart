import 'notification_reader_service.dart';

class ParsedGooglePayExpense {
  const ParsedGooglePayExpense({
    required this.name,
    required this.amount,
    required this.dateTime,
    required this.primaryCategory,
    required this.detailLabels,
  });

  final String name;
  final double amount;
  final DateTime dateTime;
  final String primaryCategory;
  final List<String> detailLabels;
}

class _CategorySuggestion {
  const _CategorySuggestion({
    required this.primaryCategory,
    required this.detailLabels,
  });

  final String primaryCategory;
  final List<String> detailLabels;
}

abstract final class GooglePayNotificationParser {
  static final List<RegExp> _amountPatterns = <RegExp>[
    RegExp(
      r'(?:(?:COP|COL\$|USD|EUR|GBP|INR|MXN|ARS|BRL|PEN|S\/|R\$|\$)\s*([0-9][0-9.,\s]{0,18}[0-9]))',
      caseSensitive: false,
    ),
    RegExp(
      r'([0-9][0-9.,\s]{0,18}[0-9])\s*(?:COP|COL\$|USD|EUR|GBP|INR|MXN|ARS|BRL|PEN|S\/|R\$|\$)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:paid|spent|purchase|payment|pagaste|pago|compra|transaccion|debited|charged)\D{0,12}([0-9][0-9.,\s]{0,18}[0-9])',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _merchantPatterns = <RegExp>[
    RegExp(
      r"\b(?:at|to|merchant)\s+([A-Za-z0-9][A-Za-z0-9 &.'\-]{1,50})",
      caseSensitive: false,
    ),
    RegExp(
      r"\b(?:en|comercio)\s+([A-Za-z0-9][A-Za-z0-9 &.'\-]{1,50})",
      caseSensitive: false,
    ),
  ];

  static final RegExp _amountLikeTextPattern = RegExp(
    r'(?:\$|cop|usd|eur|gbp|inr|mxn|ars|brl|pen|r\$)\s*[0-9]|[0-9][0-9.,\s]{2,}\s*(?:cop|usd|eur|gbp|inr|mxn|ars|brl|pen|r\$|\$)',
    caseSensitive: false,
  );

  static const List<String> _expenseSignals = <String>[
    'paid',
    'spent',
    'purchase',
    'payment',
    'charged',
    'debited',
    'transaction',
    'pagaste',
    'pago',
    'compra',
    'transaccion',
    'compra realizada',
    'pago realizado',
  ];

  static const List<String> _ignoredSignals = <String>[
    'received',
    'refund',
    'cashback',
    'reward',
    'money received',
    'dinero recibido',
    'reembolso',
    'card added',
    'tarjeta agregada',
    'setup',
    'configura',
  ];

  static const List<String> _genericTitles = <String>[
    'google pay',
    'google wallet',
    'payment successful',
    'payment complete',
    'purchase complete',
    'purchase successful',
    'compra realizada',
    'pago realizado',
    'you paid',
    'pagaste',
  ];

  static const Map<String, _CategorySuggestion> _merchantCategoryMap =
      <String, _CategorySuggestion>{
        'ubereats': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food Delivery'],
        ),
        'uber eats': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food Delivery'],
        ),
        'rappi': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food Delivery'],
        ),
        'didi food': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food Delivery'],
        ),
        'mcdonald': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'burger': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'starbucks': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'pizza': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'cafe': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'restaurant': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'restaurante': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'uber': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'lyft': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'cabify': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'didi': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'shell': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'texaco': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'terpel': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'esso': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'mobil': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'walmart': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'costco': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'carulla': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'jumbo': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'supermarket': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'supermercado': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'exito': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'spotify': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'netflix': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'disney': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'youtube': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'google one': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'prime': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'steam': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Entertainment'],
        ),
        'cinema': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Entertainment'],
        ),
        'cine': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Entertainment'],
        ),
        'walgreens': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Personal Care'],
        ),
        'cvs': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Personal Care'],
        ),
        'pharmacy': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Personal Care'],
        ),
        'farmacia': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Personal Care'],
        ),
        'movistar': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Services'],
        ),
        'claro': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Services'],
        ),
        'tigo': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Services'],
        ),
        'internet': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Utilities'],
        ),
        'electric': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Utilities'],
        ),
        'energia': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Utilities'],
        ),
        'water': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Utilities'],
        ),
        'agua': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Utilities'],
        ),
      };

  static ParsedGooglePayExpense? parse(NotificationReaderEvent event) {
    if (!_isFromGooglePay(event)) {
      return null;
    }

    final combinedText = [
      event.title,
      event.text,
      event.bigText,
      event.subText,
    ].where((value) => value.trim().isNotEmpty).join('\n');

    if (combinedText.trim().isEmpty) {
      return null;
    }

    final normalizedText = combinedText.toLowerCase();
    if (_ignoredSignals.any(normalizedText.contains)) {
      return null;
    }
    if (!_expenseSignals.any(normalizedText.contains) &&
        !_looksLikeSpendByStructure(normalizedText)) {
      return null;
    }

    final amount = _extractAmount(combinedText);
    if (amount == null || amount <= 0) {
      return null;
    }

    final merchant =
        _extractMerchant(event.title, combinedText, event.appName) ??
        'Google Pay purchase';
    final category = _categorize(merchant, combinedText);
    final postedAt = event.postedAtMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(event.postedAtMillis)
        : DateTime.now();

    return ParsedGooglePayExpense(
      name: merchant,
      amount: amount,
      dateTime: postedAt,
      primaryCategory: category.primaryCategory,
      detailLabels: category.detailLabels,
    );
  }

  static bool _isFromGooglePay(NotificationReaderEvent event) {
    final source = '${event.packageName} ${event.appName}'.toLowerCase();
    final isGooglePackage =
        source.contains('google') &&
        (source.contains('wallet') || source.contains('paisa'));
    return isGooglePackage ||
        source.contains('google pay') ||
        source.contains('google wallet');
  }

  static bool _looksLikeSpendByStructure(String text) {
    return text.contains(' at ') ||
        text.contains(' to ') ||
        text.contains(' en ') ||
        text.contains('merchant');
  }

  static double? _extractAmount(String text) {
    for (final pattern in _amountPatterns) {
      final match = pattern.firstMatch(text);
      final candidate = match?.group(1);
      if (candidate == null) {
        continue;
      }

      final parsed = _parseAmount(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  static double? _parseAmount(String rawValue) {
    var sanitized = rawValue.replaceAll(RegExp(r'[^0-9,.\s]'), '').trim();
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), '');
    if (sanitized.isEmpty) {
      return null;
    }

    final hasComma = sanitized.contains(',');
    final hasDot = sanitized.contains('.');

    if (hasComma && hasDot) {
      if (sanitized.lastIndexOf(',') > sanitized.lastIndexOf('.')) {
        sanitized = sanitized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        sanitized = sanitized.replaceAll(',', '');
      }
      return double.tryParse(sanitized);
    }

    if (hasComma) {
      final parts = sanitized.split(',');
      if (parts.length == 2 && parts.last.length <= 2) {
        sanitized = '${parts.first}.${parts.last}';
      } else {
        sanitized = sanitized.replaceAll(',', '');
      }
      return double.tryParse(sanitized);
    }

    if (hasDot) {
      final parts = sanitized.split('.');
      if (parts.length == 2 && parts.last.length <= 2) {
        return double.tryParse(sanitized);
      }
      sanitized = sanitized.replaceAll('.', '');
    }

    return double.tryParse(sanitized);
  }

  static String? _extractMerchant(
    String title,
    String combinedText,
    String appName,
  ) {
    final titleCandidate = _cleanMerchantCandidate(title);
    if (titleCandidate != null &&
        !_isGenericTitle(titleCandidate, appName) &&
        !_looksLikeAmountText(titleCandidate)) {
      return titleCandidate;
    }

    for (final pattern in _merchantPatterns) {
      final match = pattern.firstMatch(combinedText);
      final candidate = _cleanMerchantCandidate(match?.group(1));
      if (candidate != null && !_isGenericMerchant(candidate, appName)) {
        return candidate;
      }
    }

    return null;
  }

  static bool _looksLikeAmountText(String value) {
    return _amountLikeTextPattern.hasMatch(value);
  }

  static bool _isGenericTitle(String title, String appName) {
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAppName = appName.trim().toLowerCase();
    return normalizedTitle == normalizedAppName ||
        _genericTitles.contains(normalizedTitle);
  }

  static bool _isGenericMerchant(String value, String appName) {
    final normalized = value.trim().toLowerCase();
    final normalizedAppName = appName.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == normalizedAppName ||
        normalized == 'google pay' ||
        normalized == 'google wallet' ||
        normalized.startsWith('your ') ||
        normalized.startsWith('tu ') ||
        normalized == 'merchant';
  }

  static String? _cleanMerchantCandidate(String? value) {
    if (value == null) {
      return null;
    }

    var cleaned = value.trim();
    if (cleaned.isEmpty) {
      return null;
    }

    cleaned = cleaned.split(RegExp(r'[\n\r]')).first.trim();
    cleaned = cleaned
        .split(
          RegExp(
            r'\b(?:using|with|from|ending|con|desde|tarjeta|card|account)\b',
            caseSensitive: false,
          ),
        )
        .first
        .trim();
    cleaned = cleaned.replaceAll(RegExp(r'[.,:;]+$'), '').trim();

    if (cleaned.isEmpty || cleaned.length < 2) {
      return null;
    }

    return cleaned;
  }

  static _CategorySuggestion _categorize(String merchant, String fullText) {
    final normalized = '$merchant $fullText'.toLowerCase();

    for (final entry in _merchantCategoryMap.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }

    if (normalized.contains('delivery')) {
      return const _CategorySuggestion(
        primaryCategory: 'Food',
        detailLabels: <String>['Food Delivery'],
      );
    }
    if (normalized.contains('restaurant') ||
        normalized.contains('restaurante') ||
        normalized.contains('cafe')) {
      return const _CategorySuggestion(
        primaryCategory: 'Food',
        detailLabels: <String>['Food'],
      );
    }

    return const _CategorySuggestion(
      primaryCategory: 'Other',
      detailLabels: <String>[],
    );
  }
}
