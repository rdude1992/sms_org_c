import '../models/category.dart';
import '../models/sms_message.dart';

/// Retention choices offered in Settings, in days. 0 means off.
const kOtpRetentionChoices = [0, 1, 7, 30];

/// OTP messages older than [days] that the auto-delete may remove. Each must be:
/// - an OTP by the classifier's own call. A category the user set by hand
///   (`isCategoryOverridden`) is never auto-deleted, in either direction.
/// - incoming, so nothing you sent is touched
/// - not starred
/// - older than [days] before [now]
List<SmsMessage> selectOtpsToDelete(
  List<SmsMessage> messages, {
  required int days,
  required Set<int> starredIds,
  required DateTime now,
}) {
  if (days <= 0) return const [];
  final cutoff = now.subtract(Duration(days: days));
  return [
    for (final m in messages)
      if (m.category == SmsCategory.otp &&
          !m.isCategoryOverridden &&
          m.isIncoming &&
          !starredIds.contains(m.id) &&
          m.date.isBefore(cutoff))
        m,
  ];
}
