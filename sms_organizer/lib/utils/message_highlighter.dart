import '../models/category.dart';
import 'sms_extractors.dart';

/// What kind of "important" token a [TextHighlight] covers — lets the
/// widget style each one differently (e.g. green/red for a confidently
/// directional amount, accent for an account reference or OTP code).
enum HighlightKind { otp, creditAmount, debitAmount, amount, account }

class TextHighlight {
  final int start;
  final int end;
  final HighlightKind kind;
  const TextHighlight({required this.start, required this.end, required this.kind});
}

final _amountRegex = RegExp(r'(?:rs\.?|inr|₹)\s*[\d,]+(?:\.\d{1,2})?', caseSensitive: false);
final _maskedAccountRegex = RegExp(r'(?:xx|x{1,4}|\*{1,4})\s*\d{4}\b', caseSensitive: false);
final _bareAccountRegex = RegExp(r'(?:ending(?:\s+with)?|card)\s+\d{4}\b', caseSensitive: false);

/// Best-effort positions of the "important" bits of [body] to visually
/// highlight in the message bubble — the OTP code for an OTP message, or
/// the amount/account reference for a transactional one. Purely a UI
/// decoration on top of already-classified text: unlike
/// OtpExtractor/TransactionParserService (the source of truth for what's
/// actually stored and shown elsewhere in the app), a missed or
/// slightly-off match here just means one less thing gets bolded, never
/// wrong data anywhere else.
List<TextHighlight> findMessageHighlights(String body, SmsCategory category) {
  switch (category) {
    case SmsCategory.otp:
      final code = extractOtp(body);
      if (code == null) return const [];
      final start = body.indexOf(code);
      if (start < 0) return const [];
      return [TextHighlight(start: start, end: start + code.length, kind: HighlightKind.otp)];

    case SmsCategory.transactional:
      final highlights = <TextHighlight>[];

      final amountMatch = _amountRegex.firstMatch(body);
      if (amountMatch != null) {
        final kind = switch (getTransactionType(body)) {
          ParsedDirection.credit => HighlightKind.creditAmount,
          ParsedDirection.debit => HighlightKind.debitAmount,
          ParsedDirection.reversal || ParsedDirection.unknown => HighlightKind.amount,
        };
        highlights.add(TextHighlight(start: amountMatch.start, end: amountMatch.end, kind: kind));
      }

      final accountMatch = _maskedAccountRegex.firstMatch(body) ?? _bareAccountRegex.firstMatch(body);
      if (accountMatch != null) {
        highlights.add(
          TextHighlight(start: accountMatch.start, end: accountMatch.end, kind: HighlightKind.account),
        );
      }

      // Guard against the two patterns above ever matching overlapping
      // text (not expected given how different their shapes are, but a
      // silent overlap would otherwise corrupt LinkifiedText's span math).
      highlights.sort((a, b) => a.start.compareTo(b.start));
      final result = <TextHighlight>[];
      var lastEnd = -1;
      for (final h in highlights) {
        if (h.start >= lastEnd) {
          result.add(h);
          lastEnd = h.end;
        }
      }
      return result;

    case SmsCategory.personal:
    case SmsCategory.promotional:
    case SmsCategory.updates:
      return const [];
  }
}
