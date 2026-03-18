import 'dart:typed_data';

import 'package:exif/exif.dart';
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

    return _buildResult(
      text: text,
      fileName: fileName,
      metadata: metadata,
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
        if ((placemark.street ?? '').trim().isNotEmpty) placemark.street!.trim(),
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
      formattedAmount: _extractAmount(lines),
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

  String? _extractAmount(List<String> lines) {
    final totalKeywords = <String>[
      'total a pagar',
      'total pagar',
      'valor total',
      'grand total',
      'amount due',
      'amount',
      'total:',
      'total',
    ];

    double? matchedAmount;

    for (var index = 0; index < lines.length; index++) {
      final lowerLine = lines[index].toLowerCase();
      if (!totalKeywords.any(lowerLine.contains)) {
        continue;
      }

      matchedAmount ??= _extractLargestAmount(lines[index]);
      if (matchedAmount != null) {
        break;
      }

      if (index + 1 < lines.length) {
        matchedAmount = _extractLargestAmount(lines[index + 1]);
        if (matchedAmount != null) {
          break;
        }
      }
    }

    matchedAmount ??= lines
        .map(_extractLargestAmount)
        .whereType<double>()
        .fold<double?>(null, (largest, value) {
          if (largest == null || value > largest) {
            return value;
          }
          return largest;
        });

    if (matchedAmount == null) {
      return null;
    }

    final hasDecimals = matchedAmount % 1 != 0;
    final formatter = NumberFormat(
      hasDecimals ? '#,##0.00' : '#,##0',
      'en_US',
    );
    return formatter.format(matchedAmount);
  }

  double? _extractLargestAmount(String line) {
    final matches = RegExp(
      r'(?:(?:cop|usd|eur)\s*)?[$]?\s*\d[\d.,]*',
      caseSensitive: false,
    ).allMatches(line);

    double? largest;
    for (final match in matches) {
      final value = _parseAmount(match.group(0));
      if (value == null) {
        continue;
      }
      if (largest == null || value > largest) {
        largest = value;
      }
    }
    return largest;
  }

  double? _parseAmount(String? rawAmount) {
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
    final timeRegex = RegExp(
      r'(\d{1,2}:\d{2}(?::\d{2})?\s?(?:am|pm|AM|PM)?)',
    );

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

  int _max(int first, int second) => first > second ? first : second;
}

class _ReceiptMetadata {
  const _ReceiptMetadata({this.dateTime, this.location});

  final DateTime? dateTime;
  final ReceiptScanLocation? location;
}
