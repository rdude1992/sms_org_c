import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _prefKey = 'dark_mode_enabled';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getBool(_prefKey);
    if (stored == null) {
      _mode = ThemeMode.system;
    } else {
      _mode = stored ? ThemeMode.dark : ThemeMode.light;
    }
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
}
