import 'dart:async';
import 'package:flutter/services.dart';
import '../models/sim_info.dart';
import '../models/sms_message.dart';

/// Everything that has to cross into native Android code goes through here.
/// Kept as a single narrow seam so the rest of the app never touches
/// MethodChannel directly.
///
/// This is a singleton (not just "usually constructed once") because it
/// registers a [MethodChannel.setMethodCallHandler] for native-to-Dart calls
/// (see [onNotificationThreadTapped]) — a channel only has one active
/// handler at a time, so a second instance would silently steal it from the
/// first. Always use [SmsPlatformService.instance].
class SmsPlatformService {
  static final SmsPlatformService instance = SmsPlatformService._internal();

  static const _methodChannel = MethodChannel('com.smsorganizer/sms');
  static const _eventChannel = EventChannel('com.smsorganizer/sms_events');

  final _threadTappedController = StreamController<int>.broadcast();

  SmsPlatformService._internal() {
    _methodChannel.setMethodCallHandler(_handleNativeCall);
  }

  Stream<Map<String, dynamic>>? _incomingStream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationThreadTapped':
        final threadId = call.arguments as int?;
        if (threadId != null) _threadTappedController.add(threadId);
        return null;
      default:
        return null;
    }
  }

  Future<bool> isDefaultSmsApp() async {
    final result = await _methodChannel.invokeMethod<bool>('isDefaultSmsApp');
    return result ?? false;
  }

  /// Launches the system role picker. Resolves once the user has responded
  /// (accepted, dismissed, or picked a different app) — caller should
  /// re-check [isDefaultSmsApp] afterwards regardless of the boolean here.
  Future<bool> requestDefaultSmsApp() async {
    final result = await _methodChannel.invokeMethod<bool>('requestDefaultSmsApp');
    return result ?? false;
  }

  /// If the app was launched via an external sms:/smsto: link (see
  /// ComposeSmsActivity on the native side), returns the recipient/body it
  /// carried. Returns null on a normal launch.
  Future<Map<String, String?>?> getLaunchComposeExtras() async {
    final result = await _methodChannel.invokeMethod<Map?>('getLaunchComposeExtras');
    if (result == null) return null;
    return result.map((k, v) => MapEntry(k as String, v as String?));
  }

  /// If the app was cold-launched by tapping a notification (see
  /// IncomingSmsNotifier on the native side), returns the thread id it
  /// carried. Returns null on a normal launch. For the case where the app
  /// was already running, see [onNotificationThreadTapped] instead — that
  /// covers a warm tap, which arrives as a push rather than something to
  /// poll for at startup.
  Future<int?> getLaunchNotificationThreadId() async {
    return _methodChannel.invokeMethod<int>('getLaunchNotificationThreadId');
  }

  /// Fires when a notification is tapped while the app's Flutter engine is
  /// already alive (backgrounded, not killed) — MainActivity forwards this
  /// from onNewIntent. For a cold start, use [getLaunchNotificationThreadId]
  /// instead, since onNewIntent doesn't fire when there's no existing
  /// Activity instance to redeliver the intent to.
  Stream<int> get onNotificationThreadTapped => _threadTappedController.stream;

  /// Opens the system Contacts app's detail page for whichever saved
  /// contact matches [number] — see ThreadScreen's tap-to-open-contact
  /// action. Returns false (no match, no Contacts app to handle it, etc.)
  /// rather than throwing.
  Future<bool> openContact(String number) async {
    final result = await _methodChannel.invokeMethod<bool>('openContact', {'number': number});
    return result ?? false;
  }

  Future<List<Map<String, String?>>> getContacts() async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>('getContacts');
    if (raw == null) return [];
    return raw
        .map((e) => Map<String, String?>.from(
              (e as Map).map((k, v) => MapEntry(k as String, v as String?)),
            ))
        .toList();
  }

  /// Muted-category names, persisted in NATIVE SharedPreferences so the
  /// background BroadcastReceiver (no Flutter engine) can read the same
  /// data when deciding whether to post a notification.
  Future<Set<String>> getMutedCategories() async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>('getMutedCategories');
    return (raw ?? const []).map((e) => e as String).toSet();
  }

  Future<void> setMutedCategories(Set<String> categories) async {
    await _methodChannel.invokeMethod('setMutedCategories', {'categories': categories.toList()});
  }

  /// The channel's real current importance as configured in Android system
  /// settings (which the user may have changed directly there, independent
  /// of this app's own mute toggle) — see [NotificationImportance].
  Future<int> getChannelImportance(String channelId) async {
    final result =
        await _methodChannel.invokeMethod<int>('getChannelImportance', {'channelId': channelId});
    return result ?? NotificationImportance.unspecified;
  }

  /// Deep-links into the OS's per-channel notification settings (sound,
  /// vibration, badge, priority conversation) for [channelId].
  Future<void> openChannelSettings(String channelId) async {
    await _methodChannel.invokeMethod('openChannelSettings', {'channelId': channelId});
  }

  Future<List<SmsMessage>> getAllMessages() async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>('getAllMessages');
    if (raw == null) return [];
    return raw
        .map((e) => SmsMessage.fromPlatformMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  /// [subscriptionId] picks which SIM sends it on a dual-SIM device — omit
  /// to use the device's default.
  Future<bool> sendSms(String address, String body, {int? subscriptionId}) async {
    final result = await _methodChannel.invokeMethod<bool>('sendSms', {
      'address': address,
      'body': body,
      'subscriptionId': subscriptionId,
    });
    return result ?? false;
  }

  /// Active SIMs on this device, for the compose screen's SIM picker. Empty
  /// on a single-SIM device or without READ_PHONE_STATE permission.
  Future<List<SimInfo>> getActiveSims() async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>('getActiveSims');
    if (raw == null) return [];
    return raw
        .map((e) => SimInfo.fromPlatformMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> saveDraft(String address, String body, {int? existingId}) async {
    final result = await _methodChannel.invokeMethod<int>('saveDraft', {
      'address': address,
      'body': body,
      'id': existingId,
    });
    return result ?? -1;
  }

  Future<int> markRead(List<int> ids, bool read) async {
    final result = await _methodChannel.invokeMethod<int>('markRead', {
      'ids': ids,
      'read': read,
    });
    return result ?? 0;
  }

  Future<int> deleteMessages(List<int> ids) async {
    final result = await _methodChannel.invokeMethod<int>('deleteMessages', {'ids': ids});
    return result ?? 0;
  }

  /// Bulk-writes backed-up messages back into content://sms, preserving
  /// each one's original address/body/date/type/read-state. Only succeeds
  /// as the default SMS app — throws a [PlatformException] with code
  /// `NOT_DEFAULT_SMS_APP` otherwise, so callers should check
  /// [isDefaultSmsApp] first. See BackupService/SmsProvider for the flow
  /// this backs.
  Future<int> restoreMessagesToDevice(List<Map<String, dynamic>> messages) async {
    final result =
        await _methodChannel.invokeMethod<int>('restoreMessagesToDevice', {'messages': messages});
    return result ?? 0;
  }

  /// Deletes every message currently in the device's SMS store
  /// (content://sms) — irreversible. Only succeeds as the default SMS app.
  Future<int> clearAllDeviceMessages() async {
    final result = await _methodChannel.invokeMethod<int>('clearAllDeviceMessages');
    return result ?? 0;
  }

  /// Fires whenever a new SMS arrives while the app is running (see
  /// SmsDeliverReceiver / SmsReceivedReceiver on the native side). Purely
  /// for keeping the in-app list live — notification posting itself is now
  /// fully native and doesn't depend on this at all (see IncomingSmsNotifier).
  Stream<Map<String, dynamic>> get onIncomingSms {
    _incomingStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _incomingStream!;
  }
}

/// Mirrors android.app.NotificationManager / NotificationManagerCompat's
/// IMPORTANCE_* constants — plain ints (not an enum) since that's exactly
/// what [SmsPlatformService.getChannelImportance] hands back off the
/// platform channel.
class NotificationImportance {
  NotificationImportance._();

  static const unspecified = -1000;
  static const none = 0;
  static const min = 1;
  static const low = 2;
  static const defaultImportance = 3;
  static const high = 4;
  static const max = 5;

  /// True once the OS itself has silenced this channel (blocked, or
  /// downgraded to no sound/no peek) — independent of, and possibly out of
  /// sync with, this app's own per-category mute toggle.
  static bool isSilencedByOs(int importance) => importance >= none && importance <= low;
}
