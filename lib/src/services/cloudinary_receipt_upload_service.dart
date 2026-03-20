import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CloudinaryReceiptUploadService {
  static const String _defaultCloudName = 'dpvrhtjka';
  static const String _defaultUploadPreset = 'SpendAnt';

  static const String cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: _defaultCloudName,
  );
  static const String uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: _defaultUploadPreset,
  );

  Future<String> uploadReceipt({
    required int userId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (cloudName.trim().isEmpty || uploadPreset.trim().isEmpty) {
      throw StateError('Cloudinary configuration is missing.');
    }

    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
            ),
          )
          ..fields['upload_preset'] = uploadPreset
          ..fields['folder'] = 'receipts/$userId'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: fileName.trim().isEmpty
                  ? 'receipt.jpg'
                  : fileName.trim(),
            ),
          );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Cloudinary upload failed with status ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Cloudinary upload returned an invalid payload.');
    }

    final secureUrl = decoded['secure_url'];
    if (secureUrl is! String || secureUrl.trim().isEmpty) {
      throw StateError('Cloudinary upload did not return a secure_url.');
    }

    return secureUrl.trim();
  }
}
