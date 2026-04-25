/// Returns true when [value] is a non-empty, well-formed http/https URL.
///
/// Used to distinguish Cloudinary/remote receipt URLs from local file paths
/// that may be stored in the same field on older records (legacy data).
bool looksLikeRemoteUrl(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return false;
  final uri = Uri.tryParse(normalized);
  return uri != null &&
      uri.hasScheme &&
      (uri.isScheme('http') || uri.isScheme('https'));
}
