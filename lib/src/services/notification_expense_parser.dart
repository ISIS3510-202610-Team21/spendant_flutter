import 'notification_reader_service.dart';

class ParsedNotificationExpense {
  const ParsedNotificationExpense({
    required this.name,
    required this.amount,
    required this.dateTime,
    required this.primaryCategory,
    required this.detailLabels,
    required this.source,
    this.locationName,
  });

  final String name;
  final double amount;
  final DateTime dateTime;
  final String primaryCategory;
  final List<String> detailLabels;
  final String source;
  final String? locationName;
}

class _CategorySuggestion {
  const _CategorySuggestion({
    required this.primaryCategory,
    required this.detailLabels,
  });

  final String primaryCategory;
  final List<String> detailLabels;
}

abstract final class NotificationExpenseParser {
  static final List<RegExp> _amountPatterns = <RegExp>[
    RegExp(
      r'(?:(?:total\s+cop|cop|col\$|usd|eur|gbp|inr|mxn|ars|brl|pen|s/|r\$|\$)\s*([0-9][0-9.,\s]{0,18}[0-9]))',
      caseSensitive: false,
    ),
    RegExp(
      r'([0-9][0-9.,\s]{0,18}[0-9])\s*(?:cop|col\$|usd|eur|gbp|inr|mxn|ars|brl|pen|s/|r\$|\$)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:paid|spent|purchase|payment|pagaste|pago|compra|transaccion|debited|charged)\D{0,14}([0-9][0-9.,\s]{0,18}[0-9])',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _merchantPatterns = <RegExp>[
    RegExp(
      r"\b(?:compra\s+en|pagaste\s+en|pagaste\s+a|en|at|to|merchant|comercio)\s+([A-Za-z0-9][A-Za-z0-9 &.'-]{1,60})",
      caseSensitive: false,
    ),
  ];

  static final RegExp _amountLikeTextPattern = RegExp(
    r'(?:\$|cop|usd|eur|gbp|inr|mxn|ars|brl|pen|r\$)\s*[0-9]|[0-9][0-9.,\s]{2,}\s*(?:cop|usd|eur|gbp|inr|mxn|ars|brl|pen|r\$|\$)',
    caseSensitive: false,
  );

  static const List<String> _addressSignals = <String>[
    'carrera',
    'cra',
    'calle',
    'cl',
    'avenida',
    'av',
    'diagonal',
    'diag',
    'transversal',
    'tv',
    'bogota',
  ];

  static const List<String> _gmailPurchaseSignals = <String>[
    'compra',
    'transaccion aprobada',
    'total cop',
    'pago sin contacto',
    'metodo de cobro',
    'id transaccion',
    'subtotal',
  ];

  static const List<String> _gmailIgnoredSignals = <String>[
    'te enviaron',
    'recibiste',
    'money received',
    'dinero recibido',
    'reembolso',
    'refund',
    'otp',
    'codigo de verificacion',
  ];

  static const List<String> _nequiExpenseSignals = <String>[
    'pagaste',
    'compra',
    'pago aprobado',
    'transaccion aprobada',
    'te cobraron',
    'debito',
  ];

  static const List<String> _nequiIgnoredSignals = <String>[
    'te llego',
    'recibiste',
    'te enviaron',
    'recarga',
    'bolsillo',
    'colchon',
    'retiraste',
    'sacaste',
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
        'bold': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'cafe': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'cafeteria': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'restaurante': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'restaurant': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'pizza': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Food'],
        ),
        'uber': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'didi': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'cabify': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'terpel': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'shell': _CategorySuggestion(
          primaryCategory: 'Transport',
          detailLabels: <String>['Transport'],
        ),
        'exito': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'jumbo': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'carulla': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'mercado': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'supermercado': _CategorySuggestion(
          primaryCategory: 'Food',
          detailLabels: <String>['Groceries'],
        ),
        'farmacia': _CategorySuggestion(
          primaryCategory: 'Services',
          detailLabels: <String>['Personal Care'],
        ),
        'spotify': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
        'netflix': _CategorySuggestion(
          primaryCategory: 'Other',
          detailLabels: <String>['Subscriptions'],
        ),
      };

  static ParsedNotificationExpense? parse(NotificationReaderEvent event) {
    final googlePayExpense = _parseGooglePay(event);
    if (googlePayExpense != null) {
      return googlePayExpense;
    }

    final gmailExpense = _parseGmailBold(event);
    if (gmailExpense != null) {
      return gmailExpense;
    }

    return _parseNequi(event);
  }

  static ParsedNotificationExpense? _parseGooglePay(
    NotificationReaderEvent event,
  ) {
    if (!_isFromGooglePay(event)) {
      return null;
    }

    final combinedText = _combinedText(event);
    if (combinedText.trim().isEmpty) {
      return null;
    }

    final normalizedText = combinedText.toLowerCase();
    if (_gmailIgnoredSignals.any(normalizedText.contains)) {
      return null;
    }
    if (!_looksLikeSpendByStructure(normalizedText)) {
      return null;
    }

    final amount = _extractAmount(combinedText);
    if (amount == null || amount <= 0) {
      return null;
    }

    final merchant =
        _extractMerchantFromPurchaseTitle(event.title) ??
        _extractMerchant(event.title, combinedText, event.appName) ??
        'Google Pay purchase';
    final category = _categorize(merchant, combinedText);
    final postedAt = _eventDateTime(event);

    return ParsedNotificationExpense(
      name: merchant,
      amount: amount,
      dateTime: postedAt,
      primaryCategory: category.primaryCategory,
      detailLabels: category.detailLabels,
      source: 'GOOGLE_PAY',
    );
  }

  static ParsedNotificationExpense? _parseGmailBold(
    NotificationReaderEvent event,
  ) {
    if (!_isFromGmail(event)) {
      return null;
    }

    final combinedText = _combinedText(event);
    final normalizedText = combinedText.toLowerCase();
    if (_gmailIgnoredSignals.any(normalizedText.contains)) {
      return null;
    }
    if (!_gmailPurchaseSignals.any(normalizedText.contains)) {
      return null;
    }

    final amount =
        _extractAmountFromLabeledLine(combinedText, const <String>[
          'total cop',
          'cop',
          'total',
          'subtotal',
        ]) ??
        _extractAmount(combinedText);
    if (amount == null || amount <= 0) {
      return null;
    }

    final merchant =
        _extractMerchantFromPurchaseTitle(event.title) ??
        _extractMerchantFromLineSequence(combinedText) ??
        _extractMerchant(event.title, combinedText, event.appName) ??
        'Email purchase';
    final parsedDateTime =
        _extractDateTime(combinedText) ?? _eventDateTime(event);
    final category = _categorize(merchant, combinedText);

    return ParsedNotificationExpense(
      name: merchant,
      amount: amount,
      dateTime: parsedDateTime,
      primaryCategory: category.primaryCategory,
      detailLabels: category.detailLabels,
      source: 'GMAIL',
      locationName: _extractLocationLine(combinedText),
    );
  }

  static ParsedNotificationExpense? _parseNequi(NotificationReaderEvent event) {
    if (!_isFromNequi(event)) {
      return null;
    }

    final combinedText = _combinedText(event);
    final normalizedText = combinedText.toLowerCase();
    if (_nequiIgnoredSignals.any(normalizedText.contains)) {
      return null;
    }
    if (!_nequiExpenseSignals.any(normalizedText.contains) &&
        !_looksLikeSpendByStructure(normalizedText)) {
      return null;
    }

    final amount = _extractAmount(combinedText);
    if (amount == null || amount <= 0) {
      return null;
    }

    final merchant =
        _extractMerchantFromPurchaseTitle(event.title) ??
        _extractMerchant(event.title, combinedText, event.appName) ??
        'Nequi purchase';
    final category = _categorize(merchant, combinedText);

    return ParsedNotificationExpense(
      name: merchant,
      amount: amount,
      dateTime: _eventDateTime(event),
      primaryCategory: category.primaryCategory,
      detailLabels: category.detailLabels,
      source: 'NEQUI',
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

  static bool _isFromGmail(NotificationReaderEvent event) {
    final source = '${event.packageName} ${event.appName}'.toLowerCase();
    return source.contains('gmail') || source.contains('com.google.android.gm');
  }

  static bool _isFromNequi(NotificationReaderEvent event) {
    final source = '${event.packageName} ${event.appName}'.toLowerCase();
    return source.contains('nequi');
  }

  static String _combinedText(NotificationReaderEvent event) {
    return [
      event.title,
      event.text,
      event.bigText,
      event.subText,
    ].where((value) => value.trim().isNotEmpty).join('\n');
  }

  static DateTime _eventDateTime(NotificationReaderEvent event) {
    return event.postedAtMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(event.postedAtMillis)
        : DateTime.now();
  }

  static bool _looksLikeSpendByStructure(String text) {
    return text.contains(' at ') ||
        text.contains(' to ') ||
        text.contains(' en ') ||
        text.contains('merchant') ||
        text.contains('compra') ||
        text.contains('pagaste') ||
        text.contains('transaccion aprobada');
  }

  static double? _extractAmount(String text) {
    for (final pattern in _amountPatterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        final candidate = match.group(1);
        if (candidate == null) {
          continue;
        }

        final parsed = _parseAmount(candidate);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  static double? _extractAmountFromLabeledLine(
    String text,
    List<String> labels,
  ) {
    final lines = _lines(text);
    for (final label in labels) {
      for (final line in lines) {
        if (!line.toLowerCase().contains(label)) {
          continue;
        }

        final amount = _extractAmount(line);
        if (amount != null) {
          return amount;
        }
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

  static String? _extractMerchantFromPurchaseTitle(String title) {
    final match = RegExp(
      r'(?:compra|pagaste)\s+(?:en|a)\s+(.+?)(?:\s+por\s+|\s+\$|\s+cop\b|$)',
      caseSensitive: false,
    ).firstMatch(title.trim());
    return _cleanMerchantCandidate(match?.group(1));
  }

  static String? _extractMerchantFromLineSequence(String text) {
    final lines = _lines(text);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final amount = _extractAmount(line);
      if (amount == null) {
        continue;
      }

      if (index + 1 < lines.length) {
        final candidate = _cleanMerchantCandidate(lines[index + 1]);
        if (candidate != null && !_looksLikeAmountText(candidate)) {
          return candidate;
        }
      }
    }

    return null;
  }

  static DateTime? _extractDateTime(String text) {
    final match = RegExp(
      r'(\d{4}[-/]\d{2}[-/]\d{2})\s+(\d{2}:\d{2}(?::\d{2})?)',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final rawValue = '${match.group(1)} ${match.group(2)}';
    return DateTime.tryParse(rawValue.replaceAll('/', '-'));
  }

  static String? _extractLocationLine(String text) {
    for (final line in _lines(text)) {
      final normalizedLine = line.toLowerCase();
      if (_addressSignals.any(normalizedLine.contains) &&
          RegExp(r'\d').hasMatch(line)) {
        return line;
      }
    }

    return null;
  }

  static List<String> _lines(String text) {
    return text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceFirst(RegExp(r'^\s*>>\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  static bool _looksLikeAmountText(String value) {
    return _amountLikeTextPattern.hasMatch(value);
  }

  static bool _isGenericTitle(String title, String appName) {
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAppName = appName.trim().toLowerCase();
    return normalizedTitle == normalizedAppName ||
        normalizedTitle == 'gmail' ||
        normalizedTitle == 'nequi' ||
        normalizedTitle == 'google pay' ||
        normalizedTitle == 'google wallet';
  }

  static bool _isGenericMerchant(String value, String appName) {
    final normalized = value.trim().toLowerCase();
    final normalizedAppName = appName.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == normalizedAppName ||
        normalized == 'google pay' ||
        normalized == 'google wallet' ||
        normalized == 'gmail' ||
        normalized == 'nequi' ||
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
            r'\b(?:using|with|from|ending|con|desde|tarjeta|card|account|por|for|medio de pago|metodo de cobro)\b',
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
