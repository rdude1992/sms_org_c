import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';

/// Exports the current in-memory dataset (messages + parsed transactions +
/// investments) to a single JSON file the user can save/share, and restores
/// from one.
///
/// Note on scope: this backs up the app's *view* of the data (categories,
/// parsed transactions/investments, and message metadata/content as read
/// from the SMS provider at export time). Restoring re-populates the app's
/// local cache; it does not write messages back into the Android SMS
/// provider itself, since silently mass-inserting SMS into a user's inbox
/// on restore would be surprising and is deliberately avoided here.
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

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p_join(dir.path, 'sms_organizer_backup_$timestamp.json'));
    await file.writeAsString(jsonEncode(payload));
    return file;
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
    await Share.shareXFiles([XFile(file.path)], text: 'SmartSMS backup');
  }

  Future<BackupBundle> restoreFromFile(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

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

  String p_join(String a, String b) => a.endsWith('/') ? '$a$b' : '$a/$b';
}

class BackupBundle {
  final List<SmsMessage> messages;
  final List<Transaction> transactions;
  final List<InvestmentEvent> investments;

  BackupBundle({required this.messages, required this.transactions, required this.investments});
}
