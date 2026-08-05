/// Centralised regex/keyword rules. Kept in one file so categorisation
/// accuracy can be tuned without hunting through service classes.
class RegexPatterns {
  // ---- OTP ----
  static final otp = RegExp(
    r'\b(otp|one[\s-]?time password|verification code|security code)\b',
    caseSensitive: false,
  );
  static final otpNumber = RegExp(r'\b\d{4,8}\b(?=\s*(is your|otp|code))', caseSensitive: false);

  // ---- Promotional ----
  static final promo = RegExp(
    r'\b(sale|offer|discount|cashback\s+offer|deal|coupon|flat\s?\d+%|win\s+free|subscribe|unsubscribe|limited period|hurry|shop now|t&c apply)\b',
    caseSensitive: false,
  );
  static final promoSenderSuffixes = RegExp(r'-[A-Z]$'); // many promo senders end in -P/-T etc. (heuristic)

  // ---- Transactional (bank/card/UPI) ----
  static final transactional = RegExp(
    r'\b(debited|credited|withdrawn|spent|txn|transaction|purchase of|paid to|received from|a/c|acc(?:ount)? no|available balance|avl bal|upi|imps|neft|rtgs|emi)\b',
    caseSensitive: false,
  );

  // Amount like "Rs.1,234.50", "INR 500", "₹99.00"
  static final amount = RegExp(
    r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final debitKeywords = RegExp(
    r'\b(debited|spent|withdrawn|paid|purchase|debit)\b',
    caseSensitive: false,
  );
  static final creditKeywords = RegExp(
    r'\b(credited|received|deposit|refund|cashback|credit)\b',
    caseSensitive: false,
  );

  static final creditCard = RegExp(r'\b(credit card|card ending|cc\b)\b', caseSensitive: false);
  static final debitCard = RegExp(r'\b(debit card)\b', caseSensitive: false);
  static final upi = RegExp(r'\b(upi|vpa|@[a-z]+bank|@ybl|@paytm|@ibl)\b', caseSensitive: false);
  static final bankAccount = RegExp(r'\b(a/c|acc(?:ount)? no|account)\b', caseSensitive: false);

  // Last 4 digits of a card/account, e.g. "XX1234", "ending 1234", "a/c no. XXXXXX1234"
  static final lastFourDigits = RegExp(r'(?:x{2,}|\*{2,}|ending\s*)(\d{4})\b', caseSensitive: false);

  static final balance = RegExp(
    r'(?:avl\s?bal|available balance|bal(?:ance)?)[:\s]*(?:rs\.?|inr|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Merchant often follows "at", "to", "on" or "info:" — best-effort only.
  static final merchant = RegExp(
    r'(?:at|to|on)\s+([A-Za-z0-9&.\-\s]{3,25})(?:\s+on|\s+dt|\.|,|$)',
    caseSensitive: false,
  );

  // ---- Investments ----
  static final mutualFundSip = RegExp(r'\bsip\b', caseSensitive: false);
  static final mutualFundGeneral = RegExp(
    r'\b(mutual fund|mf|folio|nav of|units allotted|scheme)\b',
    caseSensitive: false,
  );
  static final mutualFundRedemption = RegExp(r'\b(redeemed|redemption)\b', caseSensitive: false);
  static final stockTrade = RegExp(
    r'\b(shares? (?:bought|sold)|order executed|contract note|demat)\b',
    caseSensitive: false,
  );
  static final folio = RegExp(r'folio\s*(?:no\.?)?\s*([A-Za-z0-9\-]+)', caseSensitive: false);

  // Known bank/issuer name hints from sender ID or body (extend as needed).
  static const knownIssuers = [
    'HDFC', 'ICICI', 'SBI', 'AXIS', 'KOTAK', 'YESBANK', 'YES BANK', 'PNB',
    'BOB', 'CANARA', 'IDFC', 'INDUSIND', 'RBL', 'FEDERAL', 'AMEX',
    'PAYTM', 'PHONEPE', 'GPAY', 'SLICE', 'JUPITER',
  ];
}
