/// True if [address] looks like an actual mobile phone number (10 digits,
/// optionally with a +91/91 India country-code prefix) rather than a
/// shortcode or alphanumeric DLT sender ID (e.g. "HDFCBK", "AD-ICICIB",
/// "56161") — those are one-way notification senders that can't receive a
/// reply SMS at all. Same heuristic CategorizationService already uses to
/// decide "personal" vs "updates" (see there); factored out here so
/// ThreadScreen can reuse it to decide whether to show a reply box.
bool isPhoneNumberAddress(String address) {
  final cleaned = address.replaceFirst(RegExp(r'^\+?91'), '').replaceAll(RegExp(r'\D'), '');
  return RegExp(r'^\d{10}$').hasMatch(cleaned);
}
