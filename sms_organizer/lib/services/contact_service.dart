import 'sms_platform_service.dart';

/// A contact's name/number pair, for display in the contact picker. Kept
/// separate from the internal name->number lookup map, which dedupes by
/// normalized number and so can't reconstruct the full contact list (two
/// contacts sharing a normalized number would collapse to one entry there).
class ContactEntry {
  final String name;
  final String number;
  ContactEntry({required this.name, required this.number});
}

/// Resolves raw SMS `address` values (phone numbers, or short alphanumeric
/// sender IDs like "HDFCBK") to a saved contact's display name where
/// possible. Falls back to the raw address otherwise — short sender IDs
/// from banks/services simply won't be in the user's contacts, which is
/// expected and fine.
class ContactService {
  Map<String, String> _numberToName = {};
  List<ContactEntry> _entries = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Full contact list (name + number), for the contact picker. Sorted by
  /// name for a stable, scannable list.
  List<ContactEntry> get entries => _entries;

  Future<void> load(SmsPlatformService platform) async {
    try {
      final contacts = await platform.getContacts();
      final map = <String, String>{};
      final entries = <ContactEntry>[];
      for (final c in contacts) {
        final name = c['name'];
        final number = c['number'];
        if (name == null || number == null || name.isEmpty || number.isEmpty) continue;
        entries.add(ContactEntry(name: name, number: number));
        final normalized = _normalize(number);
        if (normalized.isNotEmpty) {
          map[normalized] = name;
        }
      }
      entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _numberToName = map;
      _entries = entries;
      _loaded = true;
    } catch (_) {
      // Contacts permission may be denied — degrade gracefully to showing
      // raw addresses rather than failing message loading entirely.
      _numberToName = {};
      _entries = [];
      _loaded = false;
    }
  }

  /// Returns the saved contact name for [address], or [address] unchanged
  /// if no match is found (e.g. bank/service sender IDs, unsaved numbers).
  String displayNameFor(String address) {
    final normalized = normalize(address);
    if (normalized.isEmpty) return address;
    return _numberToName[normalized] ?? address;
  }

  /// Normalises to the last 10 digits so "+91 98765 43210", "098765-43210",
  /// and "9876543210" all match the same contact/conversation. Short
  /// alphanumeric sender IDs (e.g. "AX-HDFCBK") have no digit run this long
  /// and normalize to a string that won't collide with real numbers, which
  /// is what we want — they're never in the contacts list anyway. Static
  /// (and public) so callers matching an address against an existing
  /// conversation — e.g. the compose screen — can reuse the exact same
  /// rule instead of re-deriving it.
  static String normalize(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 10) return digits;
    return digits.substring(digits.length - 10);
  }
}
