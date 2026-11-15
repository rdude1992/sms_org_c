import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_organizer/models/category.dart';
import 'package:sms_organizer/models/sms_message.dart';
import 'package:sms_organizer/services/categorization_service.dart';

/// Shared vectors with the native Categorizer.kt — see the fixture header.
List<(SmsCategory, String, String)> _loadCases() {
  final cases = <(SmsCategory, String, String)>[];
  for (final line in File('test/fixtures/categorization_cases.tsv').readAsLinesSync()) {
    if (line.trim().isEmpty || line.startsWith('#')) continue;
    final parts = line.split('\t');
    cases.add((SmsCategory.values.byName(parts[0]), parts[1], parts.sublist(2).join('\t')));
  }
  return cases;
}

SmsMessage _msg(String sender, String body) => SmsMessage(
      id: 1,
      threadId: 1,
      address: sender,
      body: body,
      date: DateTime(2026, 11, 15),
      box: SmsBoxType.inbox,
      read: true,
    );

void main() {
  final categorizer = CategorizationService();

  group('shared categorization fixture', () {
    for (final (expected, sender, body) in _loadCases()) {
      test('$sender: $body', () {
        expect(categorizer.categorize(_msg(sender, body)), expected);
      });
    }
  });

  group('keyword boundaries', () {
    test('short keywords do not match inside other words', () {
      expect(CategorizationService.hasKeyword('your window seat', 'win'), isFalse);
      expect(CategorizationService.hasKeyword('business hours', 'bus'), isFalse);
      expect(CategorizationService.hasKeyword('daily gossip', 'sip'), isFalse);
      expect(CategorizationService.hasKeyword('track it', 'ack'), isFalse);
    });

    test('plurals and exact words still match', () {
      expect(CategorizationService.hasKeyword('big deals today', 'deal'), isTrue);
      expect(CategorizationService.hasKeyword('your sip installment', 'sip'), isTrue);
      expect(CategorizationService.hasKeyword('amount transferred', 'transfer'), isTrue);
    });
  });
}
