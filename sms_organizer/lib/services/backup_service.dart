import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';

/// Exports the current in-memory dataset (messages + parsed transactions +
/// investments) to a single JSON file the user can save/share, and parses
/// one back into a [BackupBundle].
///
/// Note on scope: this backs up the app's *view* of the data (categories,
/// parsed transactions/investments, and message metadata/content as read
/// from the SMS provider at export time). What restoring *does* with the
/// parsed bundle is the caller's choice, not this service's: repopulating
/// the app's own local cache (SmsProvider.restoreFromBackup) is silent and
/// always safe; writing the messages back into the actual Android SMS
/// store (SmsProvider.restoreMessagesToDeviceStore) is a separate,
/// explicit, user-confirmed action — see SettingsScreen — since silently
/// mass-inserting SMS into a user's inbox would be surprising.
class BackupService {
  static const _formatVersion = 1;

  Future<File> exportToFile({
    required List<SmsMessage> messages,
    required List<Transaction> transactions,
    required List<InvestmentEvent> investments,
  }) async {
    final payload = {
      'formatVersion': _formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'messages': messages.map((m) => m.toJson()).toList(),
      'transactions': transactions.map((t) => t.toJson()).toList(),
      'investments': investments.map((i) => i.toJson()).toList(),
    };

    // Written to the temp dir, not app documents: the file holds every SMS
    // body (OTPs, bank alerts) in plain text and only needs to live long
    // enough for the share sheet's target app to read it. Older exports are
    // removed on each new one, so copies don't pile up.
    final dir = await getTemporaryDirectory();
    await _deleteOldBackups(dir);
    // Exports from older versions were left in the documents dir forever.
    await _deleteOldBackups(await getApplicationDocumentsDirectory());
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join(dir.path, '$_filePrefix$timestamp.json'));
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  static const _filePrefix = 'sms_organizer_backup_';

  Future<void> _deleteOldBackups(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith(_filePrefix)) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // Best-effort cleanup; never block an export on it.
    }
  }

  Future<void> exportAndShare({
    required List<SmsMessage> messages,
    required List<Transaction> transactions,
    required List<InvestmentEvent> investments,
  }) async {
    final file = await exportToFile(
      messages: messages,
      transactions: transactions,
      investments: investments,
    );
    // share_plus 11+ deprecated the static Share.shareXFiles in favor of
    // this instance-based API — see share_plus's CHANGELOG.
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'SmartSMS backup'));
  }

  Future<BackupBundle> restoreFromFile(File file) async {
    final content = await file.readAsString();
    // Large backups (tens of thousands of messages) take noticeable time to
    // decode, so this runs off the UI isolate.
    return Isolate.run(() => _decodeBundle(content));
  }
}

/// Top-level so the isolate closure captures nothing but [content].
BackupBundle _decodeBundle(String content) {
  final decoded = jsonDecode(content);
  if (decoded is! Map<String, dynamic> || decoded['messages'] is! List) {
    throw const FormatException('Not a SmartSMS backup file.');
  }
  final json = decoded;
  final version = json['formatVersion'];
  // Absent in the earliest exports, which were all format 1.
  if (version != null && (version is! int || version > BackupService._formatVersion)) {
    throw FormatException(
      'Unsupported backup format version $version. Update SmartSMS to restore this backup.',
    );
  }

  final messages = (json['messages'] as List<dynamic>? ?? [])
      .map((e) => SmsMessage.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
  final transactions = (json['transactions'] as List<dynamic>? ?? [])
      .map((e) => Transaction.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
  final investments = (json['investments'] as List<dynamic>? ?? [])
      .map((e) => InvestmentEvent.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();

  return BackupBundle(messages: messages, transactions: transactions, investments: investments);
}

class BackupBundle {
  final List<SmsMessage> messages;
  final List<Transaction> transactions;
  final List<InvestmentEvent> investments;

  BackupBundle({required this.messages, required this.transactions, required this.investments});
}
