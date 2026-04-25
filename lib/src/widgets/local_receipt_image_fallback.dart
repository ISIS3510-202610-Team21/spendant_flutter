import 'dart:typed_data';

import 'package:flutter/material.dart';

Widget buildLocalReceiptImage({
  required String? imagePath,
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
