import 'package:flutter/foundation.dart';
import '../models/category.dart';
import '../services/notification_preferences_service.dart';

class NotificationSettingsProvider extends ChangeNotifier {
  final NotificationPreferencesService _service = NotificationPreferencesService();

  Set<SmsCategory> _muted = {};
  Set<SmsCategory> get mutedCategories => _muted;

  bool isMuted(SmsCategory category) => _muted.contains(category);

  Future<void> load() async {
    _muted = await _service.loadMuted();
    notifyListeners();
  }

  Future<void> setMuted(SmsCategory category, bool muted) async {
    final updated = Set<SmsCategory>.from(_muted);
    if (muted) {
      updated.add(category);
    } else {
      updated.remove(category);
    }
    _muted = updated;
    notifyListeners();
    await _service.saveMuted(_muted);
  }
}
