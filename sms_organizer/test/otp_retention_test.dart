import 'package:flutter_test/flutter_test.dart';
import 'package:sms_organizer/models/category.dart';
import 'package:sms_organizer/models/sms_message.dart';
import 'package:sms_organizer/services/otp_retention.dart';

SmsMessage _msg(
  int id,
  DateTime date, {
  SmsCategory category = SmsCategory.otp,
  SmsBoxType box = SmsBoxType.inbox,
  bool overridden = false,
}) =>
    SmsMessage(
      id: id,
      threadId: 1,
      address: 'VM-HDFCBK',
      body: '123456 is your OTP',
      date: date,
      box: box,
      read: true,
      category: category,
      isCategoryOverridden: overridden,
    );

void main() {
  final now = DateTime(2026, 11, 15, 12);
  final old = now.subtract(const Duration(days: 10));

  test('selects only old, incoming, classifier OTPs that are not starred', () {
    final messages = [
      _msg(1, old), // deleted
      _msg(2, now.subtract(const Duration(hours: 2))), // too recent
      _msg(3, old, overridden: true), // user set this category: keep
      _msg(4, old, box: SmsBoxType.sent), // sent by you: keep
      _msg(5, old), // starred: keep
      _msg(6, old, category: SmsCategory.transactional), // not an OTP
    ];
    final picked = selectOtpsToDelete(messages, days: 7, starredIds: {5}, now: now);
    expect(picked.map((m) => m.id), [1]);
  });

  test('off selects nothing', () {
    expect(selectOtpsToDelete([_msg(1, old)], days: 0, starredIds: const {}, now: now), isEmpty);
  });
}
