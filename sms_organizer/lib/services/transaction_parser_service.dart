import '../models/category.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';
import '../utils/regex_patterns.dart';

class TransactionParserService {
  /// Only call this on messages already tagged [SmsCategory.transactional].
  Transaction? parseTransaction(SmsMessage message) {
    final body = message.body;

    final amountMatch = RegexPatterns.amount.firstMatch(body);
    if (amountMatch == null) return null;
    final amount = _parseAmount(amountMatch.group(1)!);
    if (amount == null) return null;

    final direction = _direction(body);
    final instrument = _instrument(body);
    final ref = RegexPatterns.lastFourDigits.firstMatch(body)?.group(1);
    final issuer = _detectIssuer(body, message.address);
    final balanceMatch = RegexPatterns.balance.firstMatch(body);
    final balance = balanceMatch != null ? _parseAmount(balanceMatch.group(1)!) : null;
    final merchant = _detectMerchant(body);

    return Transaction(
      smsId: message.id,
      date: message.date,
      amount: amount,
      direction: direction,
      instrument: instrument,
      instrumentRef: ref,
      issuer: issuer,
      merchant: merchant,
      balanceAfter: balance,
      rawBody: body,
    );
  }

  /// Only call this on messages already tagged [SmsCategory.transactional]
  /// (investment SMS reliably also contain amount + account-style language).
  InvestmentEvent? parseInvestment(SmsMessage message) {
    final body = message.body;
    final isMf = RegexPatterns.mutualFundSip.hasMatch(body) ||
        RegexPatterns.mutualFundGeneral.hasMatch(body);
    final isStock = RegexPatterns.stockTrade.hasMatch(body);
    if (!isMf && !isStock) return null;

    final amountMatch = RegexPatterns.amount.firstMatch(body);
    if (amountMatch == null) return null;
    final amount = _parseAmount(amountMatch.group(1)!);
    if (amount == null) return null;

    InvestmentKind kind;
    if (RegexPatterns.mutualFundRedemption.hasMatch(body)) {
      kind = InvestmentKind.mutualFundRedemption;
    } else if (RegexPatterns.mutualFundSip.hasMatch(body)) {
      kind = InvestmentKind.mutualFundSip;
    } else if (isMf) {
      kind = InvestmentKind.mutualFundPurchase;
    } else if (isStock) {
      kind = InvestmentKind.stockTrade;
    } else {
      kind = InvestmentKind.other;
    }

    final folio = RegexPatterns.folio.firstMatch(body)?.group(1);

    return InvestmentEvent(
      smsId: message.id,
      date: message.date,
      amount: amount,
      kind: kind,
      folioOrAccount: folio,
      rawBody: body,
    );
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  TxnDirection _direction(String body) {
    final debit = RegexPatterns.debitKeywords.hasMatch(body);
    final credit = RegexPatterns.creditKeywords.hasMatch(body);
    if (debit && !credit) return TxnDirection.debit;
    if (credit && !debit) return TxnDirection.credit;
    // Both or neither matched — fall back to whichever keyword appears first.
    final debitIdx = RegexPatterns.debitKeywords.firstMatch(body)?.start ?? -1;
    final creditIdx = RegexPatterns.creditKeywords.firstMatch(body)?.start ?? -1;
    if (debitIdx == -1 && creditIdx == -1) return TxnDirection.unknown;
    if (debitIdx == -1) return TxnDirection.credit;
    if (creditIdx == -1) return TxnDirection.debit;
    return debitIdx < creditIdx ? TxnDirection.debit : TxnDirection.credit;
  }

  InstrumentType _instrument(String body) {
    if (RegexPatterns.creditCard.hasMatch(body)) return InstrumentType.creditCard;
    if (RegexPatterns.debitCard.hasMatch(body)) return InstrumentType.debitCard;
    if (RegexPatterns.upi.hasMatch(body)) return InstrumentType.upi;
    if (RegexPatterns.bankAccount.hasMatch(body)) return InstrumentType.bankAccount;
    return InstrumentType.unknown;
  }

  String? _detectIssuer(String body, String sender) {
    final upperBody = body.toUpperCase();
    final upperSender = sender.toUpperCase();
    for (final issuer in RegexPatterns.knownIssuers) {
      if (upperSender.contains(issuer) || upperBody.contains(issuer)) {
        return issuer;
      }
    }
    return null;
  }

  String? _detectMerchant(String body) {
    final match = RegexPatterns.merchant.firstMatch(body);
    return match?.group(1)?.trim();
  }
}
