import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _prefKey = 'dark_mode_enabled';
  static const _accentPrefKey = 'accent_color';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  // Null means "use the brand default" (AppTheme's own terracotta
  // light/dark pair) rather than one of the alternates in
  // AppColors.accentOptions — see AppTheme.light/dark.
  Color? _accentColor;
  Color? get accentColor => _accentColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_prefKey);
    if (stored == null) {
      _mode = ThemeMode.system;
    } else {
      _mode = stored ? ThemeMode.dark : ThemeMode.light;
    }
    final storedAccent = prefs.getInt(_accentPrefKey);
    _accentColor = storedAccent == null ? null : Color(storedAccent);
    notifyListeners();
  }

  Future<void> setDark(bool enabled) async {
    _mode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }

  Future<void> useSystemDefault() async {
    _mode = ThemeMode.system;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  /// Pass null to reset to the brand default terracotta.
  Future<void> setAccentColor(Color? color) async {
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_accentPrefKey);
    } else {
      await prefs.setInt(_accentPrefKey, color.value);
    }
  }
}
