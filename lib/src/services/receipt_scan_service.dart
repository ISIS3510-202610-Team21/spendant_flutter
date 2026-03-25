import 'dart:typed_data';

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
    this.date,
    this.time,
    this.location,
    this.rawText = '',
  });

  final String? name;
  final String? formattedAmount;
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

class ReceiptScanService {
  ReceiptScanService()
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static const List<String> _totalKeywords = <String>[
    'total a pagar',
    'total pagar',
    'valor total',
    'grand total',
    'amount due',
    'amount',
    'total:',
    'total',
  ];

  static const List<String> _identifierKeywords = <String>[
    'nit',
    'factura',
    'invoice',
    'ref',
    'referencia',
    'autorizacion',
    'aprobacion',
    'transaccion',
    'pedido',
    'orden',
    'documento',
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

    return _buildResult(text: text, fileName: fileName, metadata: metadata);
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

  ReceiptScanResult _buildResult({
    required String text,
    required String fileName,
    required _ReceiptMetadata metadata,
  }) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return ReceiptScanResult(
      name: _extractName(lines, fileName),
      formattedAmount: extractFormattedAmount(lines),
      date: _extractDate(lines) ?? metadata.dateTime,
      time: _extractTime(lines) ?? metadata.dateTime,
      location: metadata.location ?? _extractLocationFromText(lines),
      rawText: text,
    );
  }

  String? _extractName(List<String> lines, String fileName) {
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
    final matchedAmount = _selectAmountCandidate(lines)?.value;
    if (matchedAmount == null) {
      return null;
    }

    final hasDecimals = matchedAmount % 1 != 0;
    final formatter = NumberFormat(hasDecimals ? '#,##0.00' : '#,##0', 'en_US');
    return formatter.format(matchedAmount);
  }

  static _ReceiptAmountCandidate? _selectAmountCandidate(List<String> lines) {
    final candidates = <_ReceiptAmountCandidate>[];

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final lowerLine = line.toLowerCase();
      final totalKeywordScore = _totalKeywordScore(lowerLine);
      final previousKeywordScore = index > 0
          ? _totalKeywordScore(lines[index - 1].toLowerCase())
          : 0;

      candidates.addAll(
        _extractAmountCandidates(
          line,
          lineIndex: index,
          onTotalLine: totalKeywordScore > 0,
          afterTotalLine: totalKeywordScore == 0 && previousKeywordScore > 0,
          totalKeywordScore: totalKeywordScore > 0
              ? totalKeywordScore
              : previousKeywordScore,
        ),
      );
    }

    if (candidates.isEmpty) {
      return null;
    }

    return _pickPreferredCandidate(candidates);
  }

  static _ReceiptAmountCandidate? _pickPreferredCandidate(
    List<_ReceiptAmountCandidate> candidates,
  ) {
    var preferred = List<_ReceiptAmountCandidate>.from(candidates);

    final onTotalLine = preferred.where((candidate) => candidate.onTotalLine);
    if (onTotalLine.isNotEmpty) {
      preferred = onTotalLine.toList();
    } else {
      final afterTotalLine = preferred.where(
        (candidate) => candidate.afterTotalLine,
      );
      if (afterTotalLine.isNotEmpty) {
        preferred = afterTotalLine.toList();
      }
    }

    final highestKeywordScore = preferred
        .map((candidate) => candidate.totalKeywordScore)
        .fold<int>(0, (highest, score) => score > highest ? score : highest);
    if (highestKeywordScore > 0) {
      preferred = preferred
          .where(
            (candidate) => candidate.totalKeywordScore == highestKeywordScore,
          )
          .toList();
    }

    final dollarAmounts = preferred.where(
      (candidate) => candidate.hasDollarSign,
    );
    if (dollarAmounts.isNotEmpty) {
      preferred = dollarAmounts.toList();
    } else {
      final currencyTagged = preferred.where(
        (candidate) => candidate.hasCurrencyMarker,
      );
      if (currencyTagged.isNotEmpty) {
        preferred = currencyTagged.toList();
      }
    }

    final nonIdentifierAmounts = preferred.where(
      (candidate) => !candidate.looksLikeIdentifier,
    );
    if (nonIdentifierAmounts.isNotEmpty) {
      preferred = nonIdentifierAmounts.toList();
    }

    preferred.sort((left, right) {
      final valueComparison = right.value.compareTo(left.value);
      if (valueComparison != 0) {
        return valueComparison;
      }
      return left.lineIndex.compareTo(right.lineIndex);
    });

    return preferred.first;
  }

  static List<_ReceiptAmountCandidate> _extractAmountCandidates(
    String line, {
    required int lineIndex,
    required bool onTotalLine,
    required bool afterTotalLine,
    required int totalKeywordScore,
  }) {
    final matches = RegExp(
      r'(?:(?:cop|col\$|usd|eur)\s*)?[$]?\s*\d[\d.,]*(?:\s*(?:cop|col\$|usd|eur))?',
      caseSensitive: false,
    ).allMatches(line);

    final candidates = <_ReceiptAmountCandidate>[];
    for (final match in matches) {
      final rawCandidate = match.group(0);
      final value = _parseAmount(rawCandidate);
      if (value == null) {
        continue;
      }

      final normalizedRaw = rawCandidate?.toLowerCase() ?? '';
      candidates.add(
        _ReceiptAmountCandidate(
          value: value,
          lineIndex: lineIndex,
          hasDollarSign: normalizedRaw.contains(r'$'),
          hasCurrencyMarker: RegExp(
            r'(?:cop|col\$|usd|eur|\$)',
            caseSensitive: false,
          ).hasMatch(normalizedRaw),
          looksLikeIdentifier: _looksLikeIdentifierCandidate(
            rawCandidate ?? '',
            line,
          ),
          onTotalLine: onTotalLine,
          afterTotalLine: afterTotalLine,
          totalKeywordScore: totalKeywordScore,
        ),
      );
    }

    return candidates;
  }

  static int _totalKeywordScore(String lowerLine) {
    for (var index = 0; index < _totalKeywords.length; index++) {
      if (lowerLine.contains(_totalKeywords[index])) {
        return _totalKeywords.length - index;
      }
    }
    return 0;
  }

  static bool _looksLikeIdentifierCandidate(String rawCandidate, String line) {
    final normalizedLine = line.toLowerCase();
    if (_identifierKeywords.any(normalizedLine.contains)) {
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

  static double? _parseAmount(String? rawAmount) {
    if (rawAmount == null || rawAmount.isEmpty) {
      return null;
    }

    var cleaned = rawAmount.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (cleaned.isEmpty) {
      return null;
    }

    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    final lastSeparatorIndex = _max(lastDot, lastComma);

    if (lastSeparatorIndex != -1) {
      final decimalDigits = cleaned.length - lastSeparatorIndex - 1;
      final decimalSeparator = cleaned[lastSeparatorIndex];

      if (decimalDigits == 1 || decimalDigits == 2) {
        cleaned = cleaned
            .replaceAll(decimalSeparator == '.' ? ',' : '.', '')
            .replaceFirst(decimalSeparator, '.');
      } else {
        cleaned = cleaned.replaceAll(RegExp(r'[,.]'), '');
      }
    }

    return double.tryParse(cleaned);
  }

  DateTime? _extractDate(List<String> lines) {
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

  DateTime? _normalizeDate(String rawDate) {
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

  DateTime? _extractTime(List<String> lines) {
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

  DateTime? _normalizeTime(String rawTime) {
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

  ReceiptScanLocation? _extractLocationFromText(List<String> lines) {
    final locationKeywords = <String>[
      'calle',
      'carrera',
      'cra',
      'cl',
      'av',
      'avenida',
      'transversal',
      'diagonal',
      'direccion',
      '#',
    ];

    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      if (!locationKeywords.any(lowerLine.contains)) {
        continue;
      }

      return ReceiptScanLocation(label: line);
    }

    return null;
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
}

class _ReceiptMetadata {
  const _ReceiptMetadata({this.dateTime, this.location});

  final DateTime? dateTime;
  final ReceiptScanLocation? location;
}

class _ReceiptAmountCandidate {
  const _ReceiptAmountCandidate({
    required this.value,
    required this.lineIndex,
    required this.hasDollarSign,
    required this.hasCurrencyMarker,
    required this.looksLikeIdentifier,
    required this.onTotalLine,
    required this.afterTotalLine,
    required this.totalKeywordScore,
  });

  final double value;
  final int lineIndex;
  final bool hasDollarSign;
  final bool hasCurrencyMarker;
  final bool looksLikeIdentifier;
  final bool onTotalLine;
  final bool afterTotalLine;
  final int totalKeywordScore;
}
