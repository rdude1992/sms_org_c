import '../models/category.dart';
import '../models/sms_message.dart';
import '../utils/regex_patterns.dart';

/// Rule-based classifier. Deliberately checked in this priority order:
/// OTP first (highest precision, short-lived and important), then
/// transactional (financial relevance), then promotional, defaulting to
/// personal. This ordering matters because a bank OTP SMS also often
/// contains transactional-sounding words like "account".
class CategorizationService {
  SmsCategory categorize(SmsMessage message) {
    final body = message.body;
    final sender = message.address;

    if (_looksLikeOtp(body)) return SmsCategory.otp;
    if (_looksLikeTransactional(body, sender)) return SmsCategory.transactional;
    if (_looksLikePromotional(body, sender)) return SmsCategory.promotional;
    return SmsCategory.personal;
  }

  void categorizeAll(List<SmsMessage> messages) {
    for (final m in messages) {
      m.category = categorize(m);
    }
  }

  bool _looksLikeOtp(String body) {
    return RegexPatterns.otp.hasMatch(body) || RegexPatterns.otpNumber.hasMatch(body);
  }

  bool _looksLikeTransactional(String body, String sender) {
    if (!RegexPatterns.transactional.hasMatch(body)) return false;
    // Require an amount to reduce false positives from generic bank chatter
    // (e.g. "update your KYC") that mentions "account" without a transaction.
    return RegexPatterns.amount.hasMatch(body);
  }

  bool _looksLikePromotional(String body, String sender) {
    if (RegexPatterns.promo.hasMatch(body)) return true;
    // Common heuristic: alphanumeric sender IDs like "AX-HDFCBK" for
    // transactional vs "VM-BIGSALE" for promo aren't reliably distinguishable
    // by suffix alone, so we lean on keyword match above as the primary signal.
    return false;
  }
}
