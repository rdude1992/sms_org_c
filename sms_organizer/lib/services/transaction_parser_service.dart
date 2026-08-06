import '../models/sms_message.dart';
import '../models/transaction.dart';
import '../utils/sms_extractors.dart' as extractors;

class TransactionParserService {
  /// Only call this on messages already tagged [SmsCategory.transactional].
  Transaction? parseTransaction(SmsMessage message) {
    final body = message.body;
    final sender = message.address;

    final amount = extractors.extractAmount(body);
    if (amount == null) return null;

    return Transaction(
      smsId: message.id,
      date: message.date,
      amount: amount,
      direction: _toTxnDirection(extractors.getTransactionType(body)),
      instrument: _instrumentType(body),
      instrumentRef: extractors.extractAccountNumber(body),
      issuer: extractors.extractBankName(sender) ?? extractors.extractBankNameFromContent(body),
      merchant: extractors.extractMerchant(body),
      balanceAfter: extractors.extractBalance(body),
      entityType: _toEntityType(extractors.extractEntityType(sender, body)),
      walletType: extractors.extractWalletType(body, sender),
      billDueDate: extractors.extractBillDueDate(body),
      fastagWalletId: extractors.extractFastagWalletId(body),
      vehicleNumber: extractors.extractVehicleNumber(body),
      rawBody: body,
    );
  }

  /// Only call this on messages already tagged [SmsCategory.transactional]
  /// (investment SMS reliably also contain amount + account-style language).
  InvestmentEvent? parseInvestment(SmsMessage message) {
    final body = message.body;
    final sender = message.address;

    final isMf = RegExp(r'\bsip\b', caseSensitive: false).hasMatch(body) ||
        RegExp(r'\b(mutual fund|mf|folio|nav of|units allotted|scheme)\b', caseSensitive: false)
            .hasMatch(body);
    final isStock = RegExp(r'\b(shares? (?:bought|sold)|order executed|contract note|demat)\b',
            caseSensitive: false)
        .hasMatch(body);
    if (!isMf && !isStock) return null;

    final amount = extractors.extractAmount(body);
    if (amount == null) return null;

    InvestmentKind kind;
    if (RegExp(r'\b(redeemed|redemption)\b', caseSensitive: false).hasMatch(body)) {
      kind = InvestmentKind.mutualFundRedemption;
    } else if (RegExp(r'\bsip\b', caseSensitive: false).hasMatch(body)) {
      kind = InvestmentKind.mutualFundSip;
    } else if (isMf) {
      kind = InvestmentKind.mutualFundPurchase;
    } else {
      kind = InvestmentKind.stockTrade;
    }

    final details = extractors.extractInvestmentDetails(body, sender);

    return InvestmentEvent(
      smsId: message.id,
      date: message.date,
      amount: amount,
      kind: kind,
      fundOrScheme: details.investmentName,
      folioOrAccount: details.folio,
      units: details.units,
      nav: details.nav,
      amc: details.amc,
      rawBody: body,
    );
  }

  /// UPI first (VPA-style address or explicit "upi"/"vpa" mention), then
  /// [extractCardTypeHint] to pick credit vs debit card, then a generic
  /// bank-account mention, else unknown.
  InstrumentType _instrumentType(String content) {
    if (RegExp(r'\b(upi|vpa)\b', caseSensitive: false).hasMatch(content) ||
        RegExp(r'[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+').hasMatch(content)) {
      return InstrumentType.upi;
    }

    final cardHint = extractors.extractCardTypeHint(content);
    if (cardHint == 'credit') return InstrumentType.creditCard;
    if (cardHint == 'debit') return InstrumentType.debitCard;

    if (RegExp(r'\b(a\/c|acc(?:ount)? no|account)\b', caseSensitive: false).hasMatch(content)) {
      return InstrumentType.bankAccount;
    }

    return InstrumentType.unknown;
  }

  TxnDirection _toTxnDirection(extractors.ParsedDirection direction) {
    switch (direction) {
      case extractors.ParsedDirection.credit:
        return TxnDirection.credit;
      case extractors.ParsedDirection.debit:
        return TxnDirection.debit;
      case extractors.ParsedDirection.reversal:
        return TxnDirection.reversal;
      case extractors.ParsedDirection.unknown:
        return TxnDirection.unknown;
    }
  }

  EntityType _toEntityType(extractors.ParsedEntityType entityType) {
    switch (entityType) {
      case extractors.ParsedEntityType.bank:
        return EntityType.bank;
      case extractors.ParsedEntityType.wallet:
        return EntityType.wallet;
      case extractors.ParsedEntityType.investment:
        return EntityType.investment;
      case extractors.ParsedEntityType.cardService:
        return EntityType.cardService;
      case extractors.ParsedEntityType.unknown:
        return EntityType.unknown;
    }
  }
}
