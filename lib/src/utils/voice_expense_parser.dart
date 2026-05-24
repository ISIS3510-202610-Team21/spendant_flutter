abstract final class VoiceExpenseParser {
  static ({double? amount, String name}) parse(String rawText) {
    var clean = rawText
        .replaceAll(RegExp(r'\bpesos?\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bcop\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final lower = clean.toLowerCase();

    // 1. Digit number: 5000, 5.000, 5,000
    final digitMatch = RegExp(r'\b(\d{1,3}(?:[.,]\d{3})*|\d+)\b').firstMatch(lower);
    if (digitMatch != null) {
      final normalized = digitMatch.group(1)!.replaceAll('.', '').replaceAll(',', '.');
      final amount = double.tryParse(normalized);
      if (amount != null && amount > 0) {
        final name = clean
            .replaceFirst(
              RegExp(RegExp.escape(digitMatch.group(0)!), caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
        return (amount: amount, name: name);
      }
    }

    // 2. Spanish word-mil patterns (covers typical COP expense range)
    for (final entry in _milPatterns.entries) {
      final match = entry.key.firstMatch(lower);
      if (match != null) {
        final name = clean
            .replaceFirst(
              RegExp(RegExp.escape(match.group(0)!), caseSensitive: false),
              '',
            )
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
        return (amount: entry.value.toDouble(), name: name);
      }
    }

    return (amount: null, name: rawText.trim());
  }

  static final Map<RegExp, int> _milPatterns = {
    RegExp(r'\bcien\s+mil\b'): 100000,
    RegExp(r'\bnoventa\s+mil\b'): 90000,
    RegExp(r'\bochenta\s+mil\b'): 80000,
    RegExp(r'\bsetenta\s+mil\b'): 70000,
    RegExp(r'\bsesenta\s+mil\b'): 60000,
    RegExp(r'\bcincuenta\s+mil\b'): 50000,
    RegExp(r'\bcuarenta\s+mil\b'): 40000,
    RegExp(r'\btreinta\s+mil\b'): 30000,
    RegExp(r'\bveinticinco\s+mil\b'): 25000,
    RegExp(r'\bveinte\s+mil\b'): 20000,
    RegExp(r'\bquince\s+mil\b'): 15000,
    RegExp(r'\bdoce\s+mil\b'): 12000,
    RegExp(r'\bonce\s+mil\b'): 11000,
    RegExp(r'\bdiez\s+mil\b'): 10000,
    RegExp(r'\bnueve\s+mil\b'): 9000,
    RegExp(r'\bocho\s+mil\b'): 8000,
    RegExp(r'\bsiete\s+mil\b'): 7000,
    RegExp(r'\bseis\s+mil\b'): 6000,
    RegExp(r'\bcinco\s+mil\b'): 5000,
    RegExp(r'\bcuatro\s+mil\b'): 4000,
    RegExp(r'\btres\s+mil\b'): 3000,
    RegExp(r'\bdos\s+mil\b'): 2000,
    RegExp(r'\bun(?:a|o)?\s+mil\b|\bmil\b'): 1000,
  };
}
