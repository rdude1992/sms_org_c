import 'dart:async';
import 'package:flutter/services.dart';
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

  Future<List<SmsMessage>> getAllMessages() async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>>('getAllMessages');
    if (raw == null) return [];
    return raw
        .map((e) => SmsMessage.fromPlatformMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
  }

  Future<bool> sendSms(String address, String body) async {
    final result = await _methodChannel.invokeMethod<bool>('sendSms', {
      'address': address,
      'body': body,
    });
    return result ?? false;
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
