import 'package:flutter/foundation.dart';
import '../models/category.dart';
import '../services/notification_preferences_service.dart';
import '../services/sms_platform_service.dart';

class NotificationSettingsProvider extends ChangeNotifier {
  final NotificationPreferencesService _service = NotificationPreferencesService();

  Set<SmsCategory> _muted = {};
  Set<SmsCategory> get mutedCategories => _muted;

  bool isMuted(SmsCategory category) => _muted.contains(category);

  Future<void> load() async {
    _muted = await _service.loadMuted();
    _threadMutes = await SmsPlatformService.instance.getThreadMutes();
    notifyListeners();
  }

  // ---- Per-conversation mute (silent notifications) ----

  /// Anything this far out is "Always" (the native side stores Long.MAX_VALUE).
  static final DateTime _alwaysThreshold = DateTime(9000);

  Map<int, DateTime> _threadMutes = {};

  /// Muted-until for [threadId], or null when not muted (or the mute expired).
  DateTime? mutedUntil(int threadId) {
    final until = _threadMutes[threadId];
    if (until == null || !until.isAfter(DateTime.now())) return null;
    return until;
  }

  bool isThreadMuted(int threadId) => mutedUntil(threadId) != null;

  /// True for an "Always" mute, false for a timed one or none.
  bool isMutedForever(int threadId) => mutedUntil(threadId)?.isAfter(_alwaysThreshold) ?? false;

  /// Mutes for [duration], or until unmuted when [duration] is null.
  Future<void> muteThread(int threadId, Duration? duration) async {
    final until = duration == null ? DateTime.fromMillisecondsSinceEpoch(8640000000000000) : DateTime.now().add(duration);
    _threadMutes = {..._threadMutes, threadId: until};
    notifyListeners();
    await SmsPlatformService.instance.setThreadMute(
      threadId,
      until: duration == null ? null : until,
      forever: duration == null,
    );
  }

  Future<void> unmuteThread(int threadId) async {
    _threadMutes = Map.of(_threadMutes)..remove(threadId);
    notifyListeners();
    await SmsPlatformService.instance.setThreadMute(threadId);
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
