import 'sms_platform_service.dart';

/// Resolves raw SMS `address` values (phone numbers, or short alphanumeric
/// sender IDs like "HDFCBK") to a saved contact's display name where
/// possible. Falls back to the raw address otherwise — short sender IDs
/// from banks/services simply won't be in the user's contacts, which is
/// expected and fine.
class ContactService {
  Map<String, String> _numberToName = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load(SmsPlatformService platform) async {
    try {
      final contacts = await platform.getContacts();
      final map = <String, String>{};
      for (final c in contacts) {
        final name = c['name'];
        final number = c['number'];
        if (name == null || number == null || name.isEmpty || number.isEmpty) continue;
        final normalized = _normalize(number);
        if (normalized.isNotEmpty) {
          map[normalized] = name;
        }
      }
      _numberToName = map;
      _loaded = true;
    } catch (_) {
      // Contacts permission may be denied — degrade gracefully to showing
      // raw addresses rather than failing message loading entirely.
      _numberToName = {};
      _loaded = false;
    }
  }

  /// Returns the saved contact name for [address], or [address] unchanged
  /// if no match is found (e.g. bank/service sender IDs, unsaved numbers).
  String displayNameFor(String address) {
    final normalized = _normalize(address);
    if (normalized.isEmpty) return address;
    return _numberToName[normalized] ?? address;
  }

  /// Normalises to the last 10 digits so "+91 98765 43210", "098765-43210",
  /// and "9876543210" all match the same contact. Short alphanumeric sender
  /// IDs (e.g. "AX-HDFCBK") have no digit run this long and normalize to a
  /// string that won't collide with real numbers, which is what we want —
  /// they're never in the contacts list anyway.
  String _normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }
}
