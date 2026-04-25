import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

Widget buildLocalReceiptImage({
  required String? imagePath,
  Uint8List? imageBytes,
  BoxFit fit = BoxFit.cover,
}) {
  final normalizedImagePath = imagePath?.trim() ?? '';
  if (normalizedImagePath.isNotEmpty) {
    return Image.file(
      File(normalizedImagePath),
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return _fallbackReceiptImage(imageBytes: imageBytes, fit: fit);
      },
    );
  }

  return _fallbackReceiptImage(imageBytes: imageBytes, fit: fit);
}

Widget _fallbackReceiptImage({
  Uint8List? imageBytes,
  BoxFit fit = BoxFit.cover,
}) {
  if (imageBytes != null) {
    return Image.memory(imageBytes, fit: fit, gaplessPlayback: true);
  }

  return const DecoratedBox(
    decoration: BoxDecoration(color: Color(0xFFF1EADB)),
    child: Center(
      child: Icon(
        Icons.receipt_long_outlined,
        size: 32,
        color: Color(0xFF6F675A),
      ),
    ),
  );
}
