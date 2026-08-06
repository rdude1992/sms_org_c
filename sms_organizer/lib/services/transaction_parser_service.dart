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

    final details = extractors.extractInvestmentDetails(body, sender);

    // A one-time purchase confirmation like "as per your request 155.248
    // units at NAV 64.41 have been allotted in folio..." states units and
    // NAV but never an explicit Rs amount — extractAmount alone would
    // return null and silently drop the whole event. Derive it the same
    // way extractInvestmentDetails already derives units from amount÷NAV,
    // just inverted.
    final amount = extractors.extractAmount(body) ??
        (details.units != null && details.nav != null
            ? double.parse((details.units! * details.nav!).toStringAsFixed(2))
            : null);
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

    // extractInvestmentDetails only recognises a handful of mutual-fund
    // sender keywords; for stock trades (Zerodha/Groww/IndMoney/Kuvera)
    // the broker only shows up via the generic sender-name lookup, so fall
    // back to that rather than leaving `amc` null and losing the "group by
    // AMC/merchant" bucket for every stock trade.
    final amc = details.amc ?? extractors.extractBankName(sender);

    return InvestmentEvent(
      smsId: message.id,
      date: message.date,
      amount: amount,
      kind: kind,
      fundOrScheme: details.investmentName,
      folioOrAccount: details.folio,
      units: details.units,
      nav: details.nav,
      amc: amc,
      rawBody: body,
    );
  }

  /// [extractCardTypeHint] to pick credit vs debit card first, then a
  /// generic bank-account mention, then UPI (VPA-style address or explicit
  /// "upi"/"vpa" mention) only as a last resort.
  ///
  /// UPI is a payment *rail*, not an instrument of its own — almost every
  /// UPI SMS also names the underlying account it moved money through
  /// ("credited to a/c XX6020 ... VPA foo@bank"), so checking UPI first (as
  /// this used to) meant nearly all UPI activity for an account split off
  /// into its own "UPI" bucket instead of joining that account's other
  /// transactions. Card/account context now wins whenever it's present;
  /// UPI only remains the classification for a bare VPA/UPI mention with no
  /// account or card context at all.
  InstrumentType _instrumentType(String content) {
    final cardHint = extractors.extractCardTypeHint(content);
    if (cardHint == 'credit') return InstrumentType.creditCard;
    if (cardHint == 'debit') return InstrumentType.debitCard;

    if (RegExp(r'\b(a\/c|acc(?:ount)? no|account)\b', caseSensitive: false).hasMatch(content)) {
      return InstrumentType.bankAccount;
    }

    if (RegExp(r'\b(upi|vpa)\b', caseSensitive: false).hasMatch(content) ||
        RegExp(r'[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+').hasMatch(content)) {
      return InstrumentType.upi;
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
