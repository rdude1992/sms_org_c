import 'category.dart';

enum SmsBoxType { inbox, sent, draft, outbox, failed, queued, unknown }

SmsBoxType boxTypeFromAndroid(int type) {
  switch (type) {
    case 1:
      return SmsBoxType.inbox;
    case 2:
      return SmsBoxType.sent;
    case 3:
      return SmsBoxType.draft;
    case 4:
      return SmsBoxType.outbox;
    case 5:
      return SmsBoxType.failed;
    case 6:
      return SmsBoxType.queued;
    default:
      return SmsBoxType.unknown;
  }
}

/// Mirrors content://sms's STATUS column — Android's own delivery-report
/// tracking for a message this app *sent* (meaningless for an incoming
/// one, which is always [none]). Populated by SmsRepository.sendSms's
/// per-part sent/delivery PendingIntents on the native side (see
/// SmsSendStatusReceiver.kt) once the carrier/telephony stack reports
/// back. Many carriers never send a delivery report at all, in which case
/// this just stays [pending] forever and [SmsMessage.sendState] reads as
/// "sent" rather than "delivered" — a real SMS limitation, not a bug.
enum SmsDeliveryStatus { none, pending, delivered, failed }

SmsDeliveryStatus deliveryStatusFromAndroid(int status) {
  switch (status) {
    case 0: // Telephony.Sms.STATUS_COMPLETE
      return SmsDeliveryStatus.delivered;
    case 32: // Telephony.Sms.STATUS_PENDING
      return SmsDeliveryStatus.pending;
    case 64: // Telephony.Sms.STATUS_FAILED
      return SmsDeliveryStatus.failed;
    default: // -1 == Telephony.Sms.STATUS_NONE, or unrecognised
      return SmsDeliveryStatus.none;
  }
}

/// Outgoing-only send/delivery state — see [SmsMessage.sendState]. [failed]
/// means the send itself never reached the radio/carrier (retryable, see
/// SmsProvider.retrySend); [notDelivered] means it sent fine but the
/// carrier's delivery report came back negative (not retryable the same
/// way — resending would risk a duplicate the recipient already got).
enum OutgoingSendState { sending, sent, delivered, failed, notDelivered }

class SmsMessage {
  final int id;
  final int threadId;
  final String address;
  final String body;
  final DateTime date;
  final SmsBoxType box;
  final bool read;

  /// 0-based SIM slot this message was sent/received on ("SIM 1" = 0, "SIM
  /// 2" = 1), or null if unknown — no READ_PHONE_STATE permission, a
  /// single-SIM device, or the SIM involved has since been removed.
  final int? simSlot;

  /// Populated by CategorizationService after load; not from the OS provider.
  SmsCategory category;

  /// True once the user has manually corrected [category] via
  /// SmsProvider.setMessageCategory — see that method for why the automatic
  /// classifier never re-evaluates or overwrites it after that.
  bool isCategoryOverridden;

  /// See [SmsDeliveryStatus] — only meaningful once [box] is [SmsBoxType.sent].
  final SmsDeliveryStatus status;

  SmsMessage({
    required this.id,
    required this.threadId,
    required this.address,
    required this.body,
    required this.date,
    required this.box,
    required this.read,
    this.simSlot,
    this.category = SmsCategory.personal,
    this.isCategoryOverridden = false,
    this.status = SmsDeliveryStatus.none,
  });

  factory SmsMessage.fromPlatformMap(Map<dynamic, dynamic> map) {
    final rawSlot = map['simSlot'] as int?;
    return SmsMessage(
      id: map['id'] as int,
      threadId: (map['threadId'] ?? 0) as int,
      address: (map['address'] ?? 'Unknown') as String,
      body: (map['body'] ?? '') as String,
      date: DateTime.fromMillisecondsSinceEpoch((map['date'] ?? 0) as int),
      box: boxTypeFromAndroid((map['type'] ?? 1) as int),
      read: (map['read'] ?? true) as bool,
      simSlot: (rawSlot != null && rawSlot >= 0) ? rawSlot : null,
      status: deliveryStatusFromAndroid((map['status'] ?? -1) as int),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadId': threadId,
        'address': address,
        'body': body,
        'date': date.millisecondsSinceEpoch,
        'box': box.name,
        'read': read,
        'category': category.name,
        'categoryOverridden': isCategoryOverridden,
        'simSlot': simSlot,
        'status': status.name,
      };

  /// Inverse of [fromPlatformMap] — encodes this message back into the raw
  /// Android content://sms column shape, for writing a backup's messages
  /// into the device SMS store on restore (see
  /// SmsPlatformService.restoreMessagesToDevice). threadId/id are omitted:
  /// the provider auto-assigns a fresh id and derives thread_id from
  /// address on insert, same as [SmsRepository.sendSms] on the native side.
  Map<String, dynamic> toPlatformMap() => {
        'address': address,
        'body': body,
        'date': date.millisecondsSinceEpoch,
        'dateSent': date.millisecondsSinceEpoch,
        'type': _androidType,
        'read': read,
        'status': _androidStatus,
      };

  int get _androidType {
    switch (box) {
      case SmsBoxType.inbox:
        return 1;
      case SmsBoxType.sent:
        return 2;
      case SmsBoxType.draft:
        return 3;
      case SmsBoxType.outbox:
        return 4;
      case SmsBoxType.failed:
        return 5;
      case SmsBoxType.queued:
        return 6;
      case SmsBoxType.unknown:
        return 1;
    }
  }

  int get _androidStatus {
    switch (status) {
      case SmsDeliveryStatus.delivered:
        return 0; // Telephony.Sms.STATUS_COMPLETE
      case SmsDeliveryStatus.pending:
        return 32; // Telephony.Sms.STATUS_PENDING
      case SmsDeliveryStatus.failed:
        return 64; // Telephony.Sms.STATUS_FAILED
      case SmsDeliveryStatus.none:
        return -1; // Telephony.Sms.STATUS_NONE
    }
  }

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    final msg = SmsMessage(
      id: json['id'] as int,
      threadId: json['threadId'] as int,
      address: json['address'] as String,
      body: json['body'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      box: SmsBoxType.values.firstWhere(
        (e) => e.name == json['box'],
        orElse: () => SmsBoxType.unknown,
      ),
      read: json['read'] as bool,
      simSlot: json['simSlot'] as int?,
      status: SmsDeliveryStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SmsDeliveryStatus.none,
      ),
    );
    msg.category = SmsCategory.values.firstWhere(
      (e) => e.name == json['category'],
      orElse: () => SmsCategory.personal,
    );
    msg.isCategoryOverridden = json['categoryOverridden'] as bool? ?? false;
    return msg;
  }

  bool get isIncoming => box == SmsBoxType.inbox;

  /// Null for an incoming message (or a draft) — none of this applies.
  /// See [OutgoingSendState] for what each value means and drives in
  /// ThreadScreen's per-bubble status indicator.
  OutgoingSendState? get sendState {
    switch (box) {
      case SmsBoxType.outbox:
      case SmsBoxType.queued:
        return OutgoingSendState.sending;
      case SmsBoxType.failed:
        return OutgoingSendState.failed;
      case SmsBoxType.sent:
        if (status == SmsDeliveryStatus.delivered) return OutgoingSendState.delivered;
        if (status == SmsDeliveryStatus.failed) return OutgoingSendState.notDelivered;
        return OutgoingSendState.sent;
      case SmsBoxType.inbox:
      case SmsBoxType.draft:
      case SmsBoxType.unknown:
        return null;
    }
  }
}

/// A conversation groups all messages sharing a thread/address for the
/// chat-style ("conversational") view.
class SmsConversation {
  final int threadId;
  final String address;
  final List<SmsMessage> messages;

  SmsConversation({required this.threadId, required this.address, required this.messages});

  SmsMessage get latest => messages.first; // messages assumed sorted desc by date

  /// The first message (in current — newest-first — order) whose body
  /// contains [query] case-insensitively, or [latest] if [query] is blank
  /// or matches nothing here (e.g. this conversation matched a chat search
  /// on contact name/address instead of any message body).
  SmsMessage previewFor(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return latest;
    final lower = trimmed.toLowerCase();
    for (final m in messages) {
      if (m.body.toLowerCase().contains(lower)) return m;
    }
    return latest;
  }
  int get unreadCount => messages.where((m) => m.isIncoming && !m.read).length;
}
