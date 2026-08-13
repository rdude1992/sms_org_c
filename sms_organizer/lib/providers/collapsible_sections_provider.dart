import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists which collapsible sections (see widgets/ui/collapsible_section.dart)
/// the user has manually collapsed — Insights' "By card / account" etc. and
/// AmcDetailScreen's per-fund holding cards both read/write this, so a
/// section collapsed on one visit stays collapsed the next, instead of
/// resetting to expanded every time the screen is rebuilt.
///
/// Keyed by a caller-supplied stable string (e.g. "insights.by_merchant",
/// "amc_holding.<key>") rather than position, so adding/reordering/removing
/// sections never shuffles unrelated saved state onto the wrong section.
class CollapsibleSectionsProvider extends ChangeNotifier {
  static const _prefKey = 'collapsed_sections';

  Set<String> _collapsed = {};

  bool isCollapsed(String key) => _collapsed.contains(key);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _collapsed = (prefs.getStringList(_prefKey) ?? const []).toSet();
    notifyListeners();
  }

  Future<void> toggle(String key) async {
    if (!_collapsed.add(key)) _collapsed.remove(key);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _collapsed.toList());
  }
}
