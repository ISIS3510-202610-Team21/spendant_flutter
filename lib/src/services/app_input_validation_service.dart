import 'package:flutter/services.dart';

abstract final class AppInputValidationService {
  // Covers the major Unicode emoji blocks and combining characters.
  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F600}-\u{1F64F}]'
    r'|[\u{1F300}-\u{1F5FF}]'
    r'|[\u{1F680}-\u{1F6FF}]'
    r'|[\u{1F1E0}-\u{1F1FF}]'
    r'|[\u{2600}-\u{26FF}]'
    r'|[\u{2700}-\u{27BF}]'
    r'|[\u{FE00}-\u{FE0F}]'
    r'|[\u{1F900}-\u{1F9FF}]'
    r'|[\u{1FA00}-\u{1FAFF}]'
    r'|[\u{200D}]'
    r'|[\u{20E3}]',
    unicode: true,
  );

  static final RegExp _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  /// Returns true if [text] contains at least one emoji character.
  static bool containsEmoji(String text) => _emojiRegex.hasMatch(text);

  /// Returns true if [text] is non-empty and consists entirely of emoji
  /// characters (and whitespace) with no regular text content.
  static bool isOnlyEmoji(String text) {
    if (text.isEmpty) return false;
    final stripped = text.replaceAll(_emojiRegex, '').replaceAll(RegExp(r'\s'), '');
    return stripped.isEmpty && _emojiRegex.hasMatch(text);
  }

  /// Returns true if [email] matches standard email format:
  /// text before @, a domain, and a TLD of at least 2 characters.
  static bool isValidEmail(String email) => _emailRegex.hasMatch(email);

  /// A [TextInputFormatter] that silently drops any emoji characters typed
  /// into a field. Use this on email and password inputs.
  static TextInputFormatter get emojiBlockFormatter =>
      FilteringTextInputFormatter.deny(_emojiRegex);
}
