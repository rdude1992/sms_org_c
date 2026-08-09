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
      };

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
    );
    msg.category = SmsCategory.values.firstWhere(
      (e) => e.name == json['category'],
      orElse: () => SmsCategory.personal,
    );
    msg.isCategoryOverridden = json['categoryOverridden'] as bool? ?? false;
    return msg;
  }

  bool get isIncoming => box == SmsBoxType.inbox;
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
