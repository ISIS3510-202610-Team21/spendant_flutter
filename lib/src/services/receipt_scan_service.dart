import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ReceiptScanLocation {
  const ReceiptScanLocation({
    required this.label,
    this.latitude,
    this.longitude,
  });

  final String label;
  final double? latitude;
  final double? longitude;
}

class ReceiptScanResult {
  const ReceiptScanResult({
    this.name,
    this.formattedAmount,
    this.amountConfidence,
    this.detectedAmounts = const <ReceiptDetectedAmount>[],
    this.date,
    this.time,
    this.location,
    this.rawText = '',
  });

  final String? name;
  final String? formattedAmount;
  final String? amountConfidence;
  final List<ReceiptDetectedAmount> detectedAmounts;
  final DateTime? date;
  final DateTime? time;
  final ReceiptScanLocation? location;
  final String rawText;

  bool get hasDetectedData =>
      name != null ||
      formattedAmount != null ||
      date != null ||
      time != null ||
      location != null;
}

class ReceiptDetectedAmount {
  const ReceiptDetectedAmount({
    required this.rawText,
    required this.normalizedValue,
    required this.lineIndex,
    required this.lineText,
    required this.score,
    required this.reasons,
    this.isSelected = false,
  });

  final String rawText;
  final int normalizedValue;
  final int lineIndex;
  final String lineText;
  final int score;
  final List<String> reasons;
  final bool isSelected;
}

class ReceiptAmountAnalysis {
  const ReceiptAmountAnalysis({
    this.selected,
    this.confidence,
    this.candidates = const <ReceiptDetectedAmount>[],
  });

  final ReceiptDetectedAmount? selected;
  final String? confidence;
  final List<ReceiptDetectedAmount> candidates;

  String? get formattedSelectedAmount {
    final value = selected?.normalizedValue;
    if (value == null) {
      return null;
    }

    return NumberFormat('#,##0', 'en_US').format(value);
  }
}

class ReceiptScanService {
  ReceiptScanService()
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const List<String> _totalKeywords = <String>[
    'total exacto',
    'total cop',
    'total a pagar',
    'total pagar',
    'valor total',
    'grand total',
    'amount due',
    'tctal',
    'tctal:',
    'amount',
    'total:',
    'total',
  ];

  static const List<String> _paymentKeywords = <String>[
    'pago',
    'pagado',
    'paga con',
    'efectivo',
    'cash',
    'recibido',
    'recibe',
    'cambio',
    'vuelto',
    'change',
    'credito',
    'debito',
    'tarjeta',
    'visa',
    'mastercard',
  ];

  static const List<String> _dueKeywords = <String>[
    'por cobrar',
    'saldo',
    'monto a pagar',
    'a pagar',
    'pendiente',
  ];

  static const List<String> _subtotalKeywords = <String>[
    'subtotal',
    'sub total',
    'base',
  ];

  static const List<String> _taxKeywords = <String>[
    'iva',
    'impuesto',
    'tax',
    'rete',
    'retencion',
    'tasa',
  ];

  static const List<String> _countKeywords = <String>[
    'item',
    'items',
    'caja',
    'cajas',
    'cantidad',
    'cant',
    'articulo',
    'articulos',
    'unidad',
    'unidades',
    'producto',
    'productos',
  ];

  static const List<String> _unitKeywords = <String>[
    '/pc',
    '/und',
    '/un',
    '/u',
    '/kg',
    '/g',
    '/lt',
    '/ml',
    '@',
  ];

  static const List<String> _addressLabels = <String>[
    'direccion',
    'dirección',
    'dir',
    'direc',
    'ubicacion',
    'ubicación',
  ];

  static const List<String> _identifierKeywords = <String>[
    'nit',
    'factura',
    'invoice',
    'ticket',
    'tiquete',
    'ref',
    'referencia',
    'codigo',
    'autorizacion',
    'aprobacion',
    'transaccion',
    'trans',
    'pedido',
    'orden',
    'documento',
    'cantidad',
    'cuota',
    'cuotas',
    'correlativo',
    'serie',
    'doc',
    'id',
    'terminal',
    'lote',
  ];

  final TextRecognizer _textRecognizer;

  Future<ReceiptScanResult> scanReceipt({
    required String fileName,
    required Uint8List bytes,
    String? path,
    DateTime? fallbackTimestamp,
  }) async {
    final extension = p.extension(path ?? fileName).toLowerCase();
    final metadata = await _readMetadata(
      bytes: bytes,
      extension: extension,
      fallbackTimestamp: fallbackTimestamp,
    );

    final text = _isPdf(extension)
        ? _extractPdfText(bytes)
        : await _recognizeImageText(path);

    // OCR/PDF text extraction must run on the main isolate (ML Kit & Syncfusion
    // use platform channels). The CPU-heavy parsing — regex scoring, date/amount
    // extraction, address detection — is pure Dart and runs in a background
    // isolate via compute() so it never blocks the UI thread.
    return compute(
      _buildReceiptResult,
      _ReceiptBuildParams(text: text, fileName: fileName, metadata: metadata),
    );
  }

  void dispose() {
    _textRecognizer.close();
  }

  Future<String> _recognizeImageText(String? path) async {
    if (path == null || path.isEmpty) {
      throw StateError('The selected image could not be opened.');
    }

    final recognizedText = await _textRecognizer.processImage(
      InputImage.fromFilePath(path),
    );
    return recognizedText.text;
  }

  String _extractPdfText(Uint8List bytes) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      return PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  }

  Future<_ReceiptMetadata> _readMetadata({
    required Uint8List bytes,
    required String extension,
    DateTime? fallbackTimestamp,
  }) async {
    DateTime? metadataDateTime;
    ReceiptScanLocation? metadataLocation;

    if (_looksLikeImage(extension)) {
      final exifData = await readExifFromBytes(bytes);
      metadataDateTime = _parseExifDateTime(exifData);
      metadataLocation = await _parseExifLocation(exifData);
    }

    return _ReceiptMetadata(
      dateTime: metadataDateTime ?? fallbackTimestamp,
      location: metadataLocation,
    );
  }

  Future<ReceiptScanLocation?> _parseExifLocation(
    Map<String, IfdTag> exifData,
  ) async {
    final latitude = _gpsValuesToFloat(exifData['GPS GPSLatitude']?.values);
    final longitude = _gpsValuesToFloat(exifData['GPS GPSLongitude']?.values);
    final latitudeRef = exifData['GPS GPSLatitudeRef']?.toString();
    final longitudeRef = exifData['GPS GPSLongitudeRef']?.toString();

    if (latitude == null ||
        longitude == null ||
        latitudeRef == null ||
        longitudeRef == null) {
      return null;
    }

    final signedLatitude = latitudeRef == 'S' ? -latitude : latitude;
    final signedLongitude = longitudeRef == 'W' ? -longitude : longitude;
    final label = await _reverseGeocode(signedLatitude, signedLongitude);

    return ReceiptScanLocation(
      label: label ?? _formatCoordinateLabel(signedLatitude, signedLongitude),
      latitude: signedLatitude,
      longitude: signedLongitude,
    );
  }

  double? _gpsValuesToFloat(IfdValues? values) {
    if (values == null || values is! IfdRatios) {
      return null;
    }

    var sum = 0.0;
    var unit = 1.0;

    for (final value in values.ratios) {
      sum += value.toDouble() * unit;
      unit /= 60.0;
    }

    return sum;
  }

  Future<String?> _reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        return null;
      }

      final placemark = placemarks.first;
      final segments = <String>[
        if ((placemark.street ?? '').trim().isNotEmpty)
          placemark.street!.trim(),
        if ((placemark.locality ?? '').trim().isNotEmpty)
          placemark.locality!.trim(),
        if ((placemark.administrativeArea ?? '').trim().isNotEmpty)
          placemark.administrativeArea!.trim(),
      ];

      if (segments.isEmpty) {
        return null;
      }

      return segments.join(', ');
    } catch (_) {
      return null;
    }
  }

  String _formatCoordinateLabel(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }

  DateTime? _parseExifDateTime(Map<String, IfdTag> exifData) {
    final rawValue =
        exifData['EXIF DateTimeOriginal']?.toString() ??
        exifData['Image DateTime']?.toString();

    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    try {
      return DateFormat('yyyy:MM:dd HH:mm:ss').parse(rawValue);
    } catch (_) {
      return null;
    }
  }

  static ReceiptScanResult _buildResult({
    required String text,
    required String fileName,
    required _ReceiptMetadata metadata,
  }) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final amountAnalysis = analyzeAmounts(lines);

    return ReceiptScanResult(
      name: _extractName(lines, fileName),
      formattedAmount: amountAnalysis.formattedSelectedAmount,
      amountConfidence: amountAnalysis.confidence,
      detectedAmounts: amountAnalysis.candidates,
      date: _extractDate(lines) ?? metadata.dateTime,
      time: _extractTime(lines) ?? metadata.dateTime,
      location: metadata.location ?? _extractLocationFromText(lines),
      rawText: text,
    );
  }

  static String? _extractName(List<String> lines, String fileName) {
    final fallbackName = p.basenameWithoutExtension(fileName).trim();
    final blockedKeywords = <String>{
      'factura',
      'invoice',
      'recibo',
      'receipt',
      'nit',
      'cash',
      'sale',
      'venta',
      'fecha',
      'date',
      'hora',
      'time',
      'total',
      'subtotal',
      'tax',
      'iva',
    };

    for (final line in lines.take(6)) {
      final normalized = line.toLowerCase();
      if (line.length < 3 || !RegExp(r'[A-Za-z]').hasMatch(line)) {
        continue;
      }
      if (RegExp(r'\d{4,}').hasMatch(line)) {
        continue;
      }
      if (blockedKeywords.any(normalized.contains)) {
        continue;
      }
      return line;
    }

    return fallbackName.isEmpty ? null : fallbackName;
  }

  @visibleForTesting
  static String? extractFormattedAmount(List<String> lines) {
    return analyzeAmounts(lines).formattedSelectedAmount;
  }

  @visibleForTesting
  static ReceiptAmountAnalysis analyzeAmounts(List<String> lines) {
    final candidates = <_ReceiptAmountCandidate>[];

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final previousKeywordScore = index > 0
          ? _standaloneTotalLabelScore(_normalizeAmountLine(lines[index - 1]))
          : 0;

      candidates.addAll(
        _extractAmountCandidates(
          line,
          lineIndex: index,
          previousTotalLabelScore: previousKeywordScore,
        ),
      );
    }

    if (candidates.isEmpty) {
      return const ReceiptAmountAnalysis();
    }

    final selectedCandidate = _pickPreferredCandidate(candidates);
    final detectedAmounts = candidates
        .map(
          (candidate) => candidate.toDetectedAmount(
            isSelected: identical(candidate, selectedCandidate),
          ),
        )
        .toList(growable: false);

    return ReceiptAmountAnalysis(
      selected: selectedCandidate?.toDetectedAmount(isSelected: true),
      confidence: _estimateAmountConfidence(candidates, selectedCandidate),
      candidates: detectedAmounts,
    );
  }

  static _ReceiptAmountCandidate? _pickPreferredCandidate(
    List<_ReceiptAmountCandidate> candidates,
  ) {
    var preferred = List<_ReceiptAmountCandidate>.from(candidates);

    final withMoneySignal = preferred
        .where((candidate) => candidate.hasMoneySignal)
        .toList();
    if (withMoneySignal.isNotEmpty) {
      preferred = withMoneySignal;
    }

    final sorted = preferred..sort(_compareCandidatesForSelection);
    final selected = sorted.first;

    if (selected.score < 0) {
      return null;
    }

    return selected;
  }

  static List<_ReceiptAmountCandidate> _extractAmountCandidates(
    String line, {
    required int lineIndex,
    required int previousTotalLabelScore,
  }) {
    final matches = RegExp(
      r'(?:(?:cop|col\$|usd|eur)\s*)?-?\s*[$]?\s*\d[\dOoIlSs.,|]*(?:\s*(?:cop|col\$|usd|eur))?',
      caseSensitive: false,
    ).allMatches(line);
    final normalizedLine = _normalizeAmountLine(line);

    final candidates = <_ReceiptAmountCandidate>[];
    for (final match in matches) {
      final rawCandidate = match.group(0);
      final value = _parseAmount(rawCandidate);
      if (value == null) {
        continue;
      }

      final normalizedRaw = rawCandidate?.toLowerCase() ?? '';
      final prefix = normalizedLine.substring(0, match.start);
      final suffix = normalizedLine.substring(match.end);
      final totalKeywordScore = _keywordScoreBefore(
        prefix,
        keywords: _totalKeywords,
      );
      final dueKeywordScore = _keywordScoreBefore(
        prefix,
        keywords: _dueKeywords,
      );
      final effectiveTotalScore = totalKeywordScore > dueKeywordScore
          ? totalKeywordScore
          : dueKeywordScore;
      final nearPaymentKeyword = _hasKeywordBefore(
        prefix,
        keywords: _paymentKeywords,
      );
      final nearSubtotalKeyword = _hasKeywordBefore(
        prefix,
        keywords: _subtotalKeywords,
      );
      final nearTaxKeyword = _hasKeywordBefore(prefix, keywords: _taxKeywords);
      final nearCountKeyword = _hasKeywordBefore(
        prefix,
        keywords: _countKeywords,
      );
      final nearUnitKeyword = _hasNearbyUnitKeyword(
        before: prefix,
        after: suffix,
      );
      final onTotalLine =
          effectiveTotalScore > 0 && !nearTaxKeyword && !nearCountKeyword;
      final afterTotalLine =
          !onTotalLine &&
          previousTotalLabelScore > 0 &&
          !nearTaxKeyword &&
          !nearCountKeyword;
      final distanceToTotalKeyword = _distanceToKeywordBefore(
        prefix,
        keywords: totalKeywordScore > 0 ? _totalKeywords : _dueKeywords,
      );
      final isNegative =
          rawCandidate != null && rawCandidate.contains(RegExp(r'-'));
      final digitCount = _amountDigitCount(rawCandidate ?? '');
      final hasSeparator = (rawCandidate ?? '').contains(RegExp(r'[.,]'));
      final score = _scoreAmountCandidate(
        value: value,
        digitCount: digitCount,
        hasSeparator: hasSeparator,
        normalizedLine: normalizedLine,
        hasDollarSign: normalizedRaw.contains(r'$'),
        hasCurrencyMarker: RegExp(
          r'(?:cop|col\$|usd|eur|\$)',
          caseSensitive: false,
        ).hasMatch(normalizedRaw),
        nearPaymentKeyword: nearPaymentKeyword,
        nearSubtotalKeyword: nearSubtotalKeyword,
        nearTaxKeyword: nearTaxKeyword,
        nearCountKeyword: nearCountKeyword,
        nearUnitKeyword: nearUnitKeyword,
        looksLikeIdentifier: _looksLikeIdentifierCandidate(
          rawCandidate ?? '',
          normalizedLine,
        ),
        onTotalLine: onTotalLine,
        afterTotalLine: afterTotalLine,
        totalKeywordScore: effectiveTotalScore > 0
            ? effectiveTotalScore
            : previousTotalLabelScore,
        distanceToTotalKeyword: distanceToTotalKeyword,
        isNegative: isNegative,
      );

      candidates.add(
        _ReceiptAmountCandidate(
          rawText: rawCandidate ?? '',
          value: value,
          lineIndex: lineIndex,
          lineText: line,
          matchStart: match.start,
          hasSeparator: hasSeparator,
          hasDollarSign: normalizedRaw.contains(r'$'),
          hasCurrencyMarker: RegExp(
            r'(?:cop|col\$|usd|eur|\$)',
            caseSensitive: false,
          ).hasMatch(normalizedRaw),
          nearPaymentKeyword: nearPaymentKeyword,
          nearSubtotalKeyword: nearSubtotalKeyword,
          nearTaxKeyword: nearTaxKeyword,
          nearCountKeyword: nearCountKeyword,
          nearUnitKeyword: nearUnitKeyword,
          looksLikeIdentifier: _looksLikeIdentifierCandidate(
            rawCandidate ?? '',
            normalizedLine,
          ),
          onTotalLine: onTotalLine,
          afterTotalLine: afterTotalLine,
          totalKeywordScore: totalKeywordScore,
          distanceToTotalKeyword: distanceToTotalKeyword,
          isNegative: isNegative,
          score: score.value,
          reasons: score.reasons,
        ),
      );
    }

    return candidates;
  }

  static int _totalKeywordScore(String lowerLine) {
    for (var index = 0; index < _totalKeywords.length; index++) {
      if (_lineContainsKeyword(lowerLine, _totalKeywords[index])) {
        return _totalKeywords.length - index;
      }
    }
    return 0;
  }

  static bool _lineContainsKeyword(String lowerLine, String keyword) {
    final escapedKeyword = RegExp.escape(keyword);
    final pattern = RegExp(
      '(?<![a-z0-9])$escapedKeyword(?![a-z0-9])',
      caseSensitive: false,
    );
    return pattern.hasMatch(lowerLine);
  }

  static int _keywordScoreBefore(
    String prefix, {
    required List<String> keywords,
    int window = 28,
  }) {
    final start = prefix.length - window < 0 ? 0 : prefix.length - window;
    final context = prefix.substring(start).trimRight();

    for (var index = 0; index < keywords.length; index++) {
      if (_lineContainsKeyword(context, keywords[index])) {
        return keywords.length - index;
      }
    }

    return 0;
  }

  static bool _hasKeywordBefore(
    String prefix, {
    required List<String> keywords,
    int window = 28,
  }) {
    return _keywordScoreBefore(prefix, keywords: keywords, window: window) > 0;
  }

  static int? _distanceToKeywordBefore(
    String prefix, {
    required List<String> keywords,
    int window = 28,
  }) {
    final start = prefix.length - window < 0 ? 0 : prefix.length - window;
    final context = prefix.substring(start);
    int? bestDistance;

    for (final keyword in keywords) {
      var searchStart = 0;
      while (searchStart < context.length) {
        final keywordIndex = context.indexOf(keyword, searchStart);
        if (keywordIndex == -1) {
          break;
        }

        final distance = context.length - (keywordIndex + keyword.length);
        if (bestDistance == null || distance < bestDistance) {
          bestDistance = distance;
        }

        searchStart = keywordIndex + keyword.length;
      }
    }

    return bestDistance;
  }

  static int _standaloneTotalLabelScore(String normalizedLine) {
    final trimmed = normalizedLine.trim();
    if (trimmed.isEmpty || RegExp(r'\d').hasMatch(trimmed)) {
      return 0;
    }

    if (_countKeywords.any(
          (keyword) => _lineContainsKeyword(trimmed, keyword),
        ) ||
        _taxKeywords.any((keyword) => _lineContainsKeyword(trimmed, keyword))) {
      return 0;
    }

    final totalScore = _totalKeywordScore(trimmed);
    if (totalScore > 0) {
      return totalScore;
    }

    return _keywordScoreBefore(trimmed, keywords: _dueKeywords, window: 48);
  }

  static String _normalizeKeywordLine(String line) {
    return line
        .toLowerCase()
        .replaceAll('0', 'o')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'a')
        .replaceAll('É', 'e')
        .replaceAll('Í', 'i')
        .replaceAll('Ó', 'o')
        .replaceAll('Ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('Ã¡', 'a')
        .replaceAll('Ã©', 'e')
        .replaceAll('Ã­', 'i')
        .replaceAll('Ã³', 'o')
        .replaceAll('Ãº', 'u')
        .replaceAll('Ã±', 'n');
  }

  static bool _looksLikeIdentifierCandidate(
    String rawCandidate,
    String normalizedLine,
  ) {
    if (_identifierKeywords.any(
      (keyword) => _lineContainsKeyword(normalizedLine, keyword),
    )) {
      return true;
    }

    if (RegExp(
      r'(?:cop|col\$|usd|eur|\$)',
      caseSensitive: false,
    ).hasMatch(rawCandidate)) {
      return false;
    }

    final digitsOnly = rawCandidate.replaceAll(RegExp(r'\D'), '');
    final hasSeparator = rawCandidate.contains(RegExp(r'[.,]'));
    return !hasSeparator && digitsOnly.length >= 8;
  }

  static bool _hasNearbyUnitKeyword({
    required String before,
    required String after,
  }) {
    final prefixStart = before.length - 16 < 0 ? 0 : before.length - 16;
    final suffixEnd = after.length > 16 ? 16 : after.length;
    final context =
        '${before.substring(prefixStart)}${after.substring(0, suffixEnd)}';

    if (_unitKeywords.any(context.contains)) {
      return true;
    }

    return RegExp(
      r'(?:\b\d+\s*(?:pc|pcs|und|un|u)\b|\bx\s*\d+\b|\b\d+\s*x\b)',
      caseSensitive: false,
    ).hasMatch(context);
  }

  static String _normalizeAmountLine(String line) {
    return _normalizeKeywordLine(line);
  }

  static _ReceiptAmountScore _scoreAmountCandidate({
    required int value,
    required int digitCount,
    required bool hasSeparator,
    required String normalizedLine,
    required bool hasDollarSign,
    required bool hasCurrencyMarker,
    required bool nearPaymentKeyword,
    required bool nearSubtotalKeyword,
    required bool nearTaxKeyword,
    required bool nearCountKeyword,
    required bool nearUnitKeyword,
    required bool looksLikeIdentifier,
    required bool onTotalLine,
    required bool afterTotalLine,
    required int totalKeywordScore,
    required int? distanceToTotalKeyword,
    required bool isNegative,
  }) {
    var score = 0;
    final reasons = <String>[];

    if (onTotalLine) {
      score += 120 + (totalKeywordScore * 4);
      reasons.add('linea con total');
    } else if (afterTotalLine) {
      score += 85 + (totalKeywordScore * 3);
      reasons.add('monto debajo de total');
    }

    if (distanceToTotalKeyword != null) {
      final proximityBonus = 40 - _min(distanceToTotalKeyword, 40);
      if (proximityBonus > 0) {
        score += proximityBonus;
        reasons.add('cerca de total');
      }
    }

    if (normalizedLine.startsWith('total') ||
        normalizedLine.contains('total \$') ||
        normalizedLine.contains('total cop') ||
        normalizedLine.contains('por cobrar') ||
        normalizedLine.contains('total exacto')) {
      score += 25;
      reasons.add('frase de total fuerte');
    }

    if (hasDollarSign) {
      score += 12;
      reasons.add('simbolo monetario');
    } else if (hasCurrencyMarker) {
      score += 8;
      reasons.add('moneda detectada');
    }

    if (hasSeparator) {
      score += 10;
      reasons.add('formato monetario');
    }

    if (value >= 1000) {
      final magnitudeBonus = _min(18, value.toString().length * 2);
      score += magnitudeBonus;
      reasons.add('magnitud compatible');
    } else if (value < 100 && !hasCurrencyMarker) {
      score -= 40;
      reasons.add('valor poco probable');
    }

    if (value <= 0) {
      score -= 220;
      reasons.add('monto cero o negativo');
    }

    if (digitCount <= 2) {
      score -= 220;
      reasons.add('muy pocos digitos');
    }

    if (!hasSeparator &&
        !hasCurrencyMarker &&
        !onTotalLine &&
        !afterTotalLine &&
        digitCount >= 5) {
      score -= 220;
      reasons.add('entero largo sin formato monetario');
    }

    if (nearSubtotalKeyword) {
      score -= 120;
      reasons.add('contexto subtotal/base');
    }

    if (nearTaxKeyword) {
      score -= 120;
      reasons.add('contexto iva/impuesto');
    }

    if (nearCountKeyword) {
      score -= 220;
      reasons.add('conteo de items/cajas');
    }

    if (nearPaymentKeyword) {
      score -= 130;
      reasons.add('contexto de pago');
    }

    if (nearUnitKeyword) {
      score -= 120;
      reasons.add('precio unitario');
    }

    if (looksLikeIdentifier) {
      if (!hasSeparator &&
          !hasCurrencyMarker &&
          !onTotalLine &&
          !afterTotalLine) {
        score -= 150;
        reasons.add('parece identificador');
      } else {
        score -= 20;
        reasons.add('contexto mixto con identificador');
      }
    }

    if (isNegative) {
      score -= 70;
      reasons.add('monto negativo');
    }

    return _ReceiptAmountScore(value: score, reasons: reasons);
  }

  static String? _estimateAmountConfidence(
    List<_ReceiptAmountCandidate> candidates,
    _ReceiptAmountCandidate? selected,
  ) {
    if (selected == null) {
      return null;
    }

    final sorted = List<_ReceiptAmountCandidate>.from(candidates)
      ..sort(_compareCandidatesForSelection);
    final runnerUp = sorted.length > 1 ? sorted[1] : null;
    final scoreGap = runnerUp == null
        ? selected.score
        : selected.score - runnerUp.score;

    if ((selected.onTotalLine || selected.afterTotalLine) &&
        !selected.nearPaymentKeyword &&
        !selected.nearSubtotalKeyword &&
        !selected.nearTaxKeyword &&
        !selected.nearCountKeyword &&
        !selected.nearUnitKeyword &&
        selected.score >= 120 &&
        scoreGap >= 20) {
      return 'alto';
    }

    if (selected.score >= 70 && scoreGap >= 10) {
      return 'medio';
    }

    return 'bajo';
  }

  static int _compareCandidatesForSelection(
    _ReceiptAmountCandidate left,
    _ReceiptAmountCandidate right,
  ) {
    final scoreComparison = right.score.compareTo(left.score);
    if (scoreComparison != 0) {
      return scoreComparison;
    }

    final leftDistance = left.distanceToTotalKeyword ?? 1 << 30;
    final rightDistance = right.distanceToTotalKeyword ?? 1 << 30;
    final distanceComparison = leftDistance.compareTo(rightDistance);
    if (distanceComparison != 0) {
      return distanceComparison;
    }

    final valueComparison = right.value.compareTo(left.value);
    if (valueComparison != 0) {
      return valueComparison;
    }

    final lineComparison = left.lineIndex.compareTo(right.lineIndex);
    if (lineComparison != 0) {
      return lineComparison;
    }

    return left.matchStart.compareTo(right.matchStart);
  }

  static int _amountDigitCount(String rawAmount) {
    return _normalizeOcrAmountToken(
      rawAmount,
    ).replaceAll(RegExp(r'\D'), '').length;
  }

  static String _normalizeOcrAmountToken(String rawAmount) {
    final buffer = StringBuffer();

    for (var index = 0; index < rawAmount.length; index++) {
      final character = rawAmount[index];
      final previous = index > 0 ? rawAmount[index - 1] : '';
      final next = index + 1 < rawAmount.length ? rawAmount[index + 1] : '';

      if (RegExp(r'\d').hasMatch(character) ||
          character == ',' ||
          character == '.' ||
          character == '-') {
        buffer.write(character);
        continue;
      }

      final hasNumericNeighbor =
          _looksLikeAmountNeighbor(previous) || _looksLikeAmountNeighbor(next);
      if (!hasNumericNeighbor) {
        continue;
      }

      if (character == 'o' || character == 'O') {
        buffer.write('0');
      } else if (character == 'l' || character == 'I' || character == '|') {
        buffer.write('1');
      } else if (character == 's' || character == 'S') {
        buffer.write('5');
      }
    }

    return buffer.toString();
  }

  static bool _looksLikeAmountNeighbor(String character) {
    return RegExp(r'[\d,.\-oOlIsS|]').hasMatch(character);
  }

  static int? _parseAmount(String? rawAmount) {
    if (rawAmount == null || rawAmount.isEmpty) {
      return null;
    }

    var cleaned = _normalizeOcrAmountToken(rawAmount);
    if (cleaned.isEmpty) {
      return null;
    }

    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    final hasDot = lastDot != -1;
    final hasComma = lastComma != -1;

    if (hasDot && hasComma) {
      final decimalSeparator = lastDot > lastComma ? '.' : ',';
      final thousandsSeparator = decimalSeparator == '.' ? ',' : '.';
      final decimalIndex = decimalSeparator == '.' ? lastDot : lastComma;
      final decimalDigits = cleaned.length - decimalIndex - 1;

      cleaned = cleaned.replaceAll(thousandsSeparator, '');
      if (decimalDigits == 1 || decimalDigits == 2) {
        cleaned = cleaned.replaceFirst(decimalSeparator, '.');
      } else {
        cleaned = cleaned.replaceAll(decimalSeparator, '');
      }

      final parsed = double.tryParse(cleaned);
      return parsed?.round();
    }

    final lastSeparatorIndex = _max(lastDot, lastComma);

    if (lastSeparatorIndex != -1) {
      final decimalDigits = cleaned.length - lastSeparatorIndex - 1;
      final decimalSeparator = cleaned[lastSeparatorIndex];

      if (decimalDigits == 1 || decimalDigits == 2) {
        cleaned = cleaned
            .replaceAll(decimalSeparator == '.' ? ',' : '.', '')
            .replaceFirst(decimalSeparator, '.');
      } else if (decimalDigits == 3) {
        cleaned = cleaned.replaceAll(RegExp(r'[,.]'), '');
      } else {
        cleaned = cleaned.replaceAll(RegExp(r'[,.]'), '');
      }
    }

    final parsed = double.tryParse(cleaned);
    return parsed?.round();
  }

  static DateTime? _extractDate(List<String> lines) {
    final dateRegex = RegExp(
      r'(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4})|(\d{4}[/\-.]\d{1,2}[/\-.]\d{1,2})',
    );

    for (final line in lines) {
      final match = dateRegex.firstMatch(line);
      if (match == null) {
        continue;
      }

      final normalized = _normalizeDate(match.group(0)!);
      if (normalized != null) {
        return normalized;
      }
    }

    return null;
  }

  static DateTime? _normalizeDate(String rawDate) {
    final candidate = rawDate.trim();
    final formats = <String>[
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'dd.MM.yyyy',
      'MM/dd/yyyy',
      'MM-dd-yyyy',
      'yyyy-MM-dd',
      'yyyy/MM/dd',
      'dd/MM/yy',
      'dd-MM-yy',
      'MM/dd/yy',
      'MM-dd-yy',
    ];

    for (final format in formats) {
      try {
        return DateFormat(format).parseStrict(candidate);
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static DateTime? _extractTime(List<String> lines) {
    final timeRegex = RegExp(r'(\d{1,2}:\d{2}(?::\d{2})?\s?(?:am|pm|AM|PM)?)');

    for (final line in lines) {
      final match = timeRegex.firstMatch(line);
      if (match == null) {
        continue;
      }

      final normalized = _normalizeTime(match.group(0)!);
      if (normalized != null) {
        return normalized;
      }
    }

    return null;
  }

  static DateTime? _normalizeTime(String rawTime) {
    final candidate = rawTime.trim().replaceAll(RegExp(r'\s+'), ' ');
    final formats = <String>[
      'hh:mm a',
      'h:mm a',
      'HH:mm',
      'HH:mm:ss',
      'hh:mm:ss a',
      'h:mm:ss a',
    ];

    for (final format in formats) {
      try {
        return DateFormat(format).parseStrict(candidate);
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static ReceiptScanLocation? _extractLocationFromText(List<String> lines) {
    for (var index = 0; index < lines.length; index++) {
      final labeledAddress = _extractLabeledAddress(lines, index);
      if (labeledAddress != null) {
        return ReceiptScanLocation(label: labeledAddress);
      }
    }

    for (var index = 0; index < lines.length; index++) {
      if (_looksLikeColombianAddressLine(lines[index])) {
        final combinedAddress = _combineAddressLines(lines, index);
        return ReceiptScanLocation(label: combinedAddress);
      }
    }

    return null;
  }

  static String? _extractLabeledAddress(List<String> lines, int index) {
    final line = lines[index];
    final lowerLine = line.toLowerCase();

    for (final label in _addressLabels) {
      final match = RegExp(
        '^\\s*$label\\s*[:.-]?\\s*(.*)\$',
        caseSensitive: false,
      ).firstMatch(lowerLine);
      if (match == null) {
        continue;
      }

      final extracted = line
          .substring(match.start)
          .replaceFirst(
            RegExp('^\\s*$label\\s*[:.-]?\\s*', caseSensitive: false),
            '',
          )
          .trim();

      if (extracted.isNotEmpty && _looksLikeColombianAddressLine(extracted)) {
        return extracted;
      }

      if (index + 1 < lines.length &&
          _looksLikeColombianAddressLine(lines[index + 1])) {
        return _combineAddressLines(lines, index + 1);
      }
    }

    return null;
  }

  static bool _looksLikeColombianAddressLine(String line) {
    final normalized = line.toLowerCase();
    return RegExp(
          r'\b(?:carrera|cra|cr|calle|cl|avenida|av|diagonal|diag|transversal|tv)\b',
          caseSensitive: false,
        ).hasMatch(normalized) &&
        RegExp(r'\d').hasMatch(normalized);
  }

  static String _combineAddressLines(List<String> lines, int startIndex) {
    final segments = <String>[lines[startIndex]];

    if (startIndex + 1 < lines.length) {
      final nextLine = lines[startIndex + 1];
      final lowerNextLine = nextLine.toLowerCase();
      if (RegExp(
            r'\b(bogota|bogotá|medellin|medellín|cali|colombia)\b',
          ).hasMatch(lowerNextLine) ||
          (!_looksLikeColombianAddressLine(nextLine) &&
              RegExp(r'[A-Za-z]').hasMatch(nextLine) &&
              nextLine.length <= 40)) {
        segments.add(nextLine);
      }
    }

    return segments.join(', ');
  }

  bool _isPdf(String extension) => extension == '.pdf';

  bool _looksLikeImage(String extension) {
    return <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
    }.contains(extension);
  }

  static int _max(int first, int second) => first > second ? first : second;

  static int _min(int first, int second) => first < second ? first : second;
}

class _ReceiptMetadata {
  const _ReceiptMetadata({this.dateTime, this.location});

  final DateTime? dateTime;
  final ReceiptScanLocation? location;
}

class _ReceiptAmountCandidate {
  const _ReceiptAmountCandidate({
    required this.rawText,
    required this.value,
    required this.lineIndex,
    required this.lineText,
    required this.matchStart,
    required this.hasSeparator,
    required this.hasDollarSign,
    required this.hasCurrencyMarker,
    required this.nearPaymentKeyword,
    required this.nearSubtotalKeyword,
    required this.nearTaxKeyword,
    required this.nearCountKeyword,
    required this.nearUnitKeyword,
    required this.looksLikeIdentifier,
    required this.onTotalLine,
    required this.afterTotalLine,
    required this.totalKeywordScore,
    required this.distanceToTotalKeyword,
    required this.isNegative,
    required this.score,
    required this.reasons,
  });

  final String rawText;
  final int value;
  final int lineIndex;
  final String lineText;
  final int matchStart;
  final bool hasSeparator;
  final bool hasDollarSign;
  final bool hasCurrencyMarker;
  final bool nearPaymentKeyword;
  final bool nearSubtotalKeyword;
  final bool nearTaxKeyword;
  final bool nearCountKeyword;
  final bool nearUnitKeyword;
  final bool looksLikeIdentifier;
  final bool onTotalLine;
  final bool afterTotalLine;
  final int totalKeywordScore;
  final int? distanceToTotalKeyword;
  final bool isNegative;
  final int score;
  final List<String> reasons;

  bool get hasMoneySignal =>
      hasSeparator || hasCurrencyMarker || onTotalLine || afterTotalLine;

  ReceiptDetectedAmount toDetectedAmount({required bool isSelected}) {
    return ReceiptDetectedAmount(
      rawText: rawText,
      normalizedValue: value,
      lineIndex: lineIndex,
      lineText: lineText,
      score: score,
      reasons: reasons,
      isSelected: isSelected,
    );
  }
}

class _ReceiptAmountScore {
  const _ReceiptAmountScore({required this.value, required this.reasons});

  final int value;
  final List<String> reasons;
}

// ---------------------------------------------------------------------------
// compute() infrastructure for Task 1 — isolate-based receipt parsing
// ---------------------------------------------------------------------------

/// Plain-data carrier sent to the background isolate.
/// All fields are primitive Dart types so they cross isolate boundaries safely.
class _ReceiptBuildParams {
  const _ReceiptBuildParams({
    required this.text,
    required this.fileName,
    required this.metadata,
  });

  final String text;
  final String fileName;
  final _ReceiptMetadata metadata;
}

/// Top-level entry point required by [compute].
/// Runs in a background isolate — no platform channels allowed here.
ReceiptScanResult _buildReceiptResult(_ReceiptBuildParams params) {
  return ReceiptScanService._buildResult(
    text: params.text,
    fileName: params.fileName,
    metadata: params.metadata,
  );
}
