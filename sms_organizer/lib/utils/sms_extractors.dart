/// Ported from the project's smsParser.ts (see /mnt/project/smsParser_ts.txt
/// in Claude's environment, or wherever you keep the source in your repo).
/// Deliberately structured to mirror that file 1:1 — one function per
/// extractor, same order, same names translated to camelCase Dart
/// conventions — so future changes on the TS side can be diffed against
/// this file function-by-function rather than having to re-derive the
/// mapping from scratch.
///
/// Translation notes (JS -> Dart), in case you're porting further updates:
/// - `.includes()` -> `.contains()`
/// - `.match(regex)` (no global flag) -> `regex.firstMatch(str)`
/// - `.match(regex)` (global flag) / `matchAll` -> `regex.allMatches(str)`
/// - `match[1]` -> `match.group(1)`
/// - JS's loose `new Date(str)` has no direct Dart equivalent (Dart's
///   DateTime.parse is strict ISO-8601), so [extractBillDueDate] uses a
///   small hand-written parser instead of a literal port — see
///   [tryParseFlexibleDate].
library sms_extractors;

// ---------------------------------------------------------------------------
// extractCardType
// ---------------------------------------------------------------------------

/// Returns 'credit' or 'debit' if the message clearly indicates a card type,
/// null otherwise. Used to help pick between InstrumentType.creditCard and
/// InstrumentType.debitCard when a generic "card ending XXXX" pattern alone
/// wouldn't tell you which.
String? extractCardTypeHint(String content) {
  final lower = content.toLowerCase();

  if (lower.contains('credit card')) return 'credit';
  if (lower.contains('debit card')) return 'debit';
  if (lower.contains('gift card')) return 'debit';

  if (lower.contains('cardmember')) return 'credit';

  if (lower.contains('credited to your card') || lower.contains('credited to card')) {
    return 'credit';
  }

  if (lower.contains('card ending') || lower.contains('card xxxx')) {
    if (lower.contains('payment') || lower.contains('credited') || lower.contains('outstanding')) {
      return 'credit';
    }
    if (lower.contains('spent') || lower.contains('debited') || lower.contains('withdrawn')) {
      return 'debit';
    }
  }

  // Many banks' card-spend alerts (e.g. "Spent Rs.X On HDFC Bank Card 6408
  // At MERCHANT...SMS BLOCK CC 6408 to...") mention only "Card NNNN" with
  // no "credit"/"debit" qualifier in the sentence itself, but always carry
  // a "BLOCK CC"/"BLOCK DC" footer telling you which product it is — CC
  // (credit card) vs DC (debit card) is the bank's own disambiguator, so
  // trust it over guessing from context.
  if (lower.contains('block cc')) return 'credit';
  if (lower.contains('block dc')) return 'debit';

  return null;
}

// ---------------------------------------------------------------------------
// extractOTP
// ---------------------------------------------------------------------------

/// Extracts the actual OTP code from a message, with context awareness
/// (prefers a code near an explicit "OTP"/"code"/"pin" keyword over a
/// bare isolated digit run that could be a phone/account number).
String? extractOtp(String content) {
  final otpWithContext = RegExp(
    r'(?:otp|code|pin|passcode|password)[\s:is-]*([A-Z0-9]{4,8})',
    caseSensitive: false,
  );
  final contextMatch = otpWithContext.firstMatch(content);
  if (contextMatch != null) {
    final candidate = contextMatch.group(1);
    if (candidate != null && RegExp(r'\d').hasMatch(candidate)) {
      return candidate;
    }
  }

  final otpRegex = RegExp(r'\b\d{4,6}\b');
  for (final match in otpRegex.allMatches(content)) {
    final value = match.group(0)!;
    final beforePattern = RegExp(
      '(?:rs\\.|rs|inr|₹|xx|\\*|ending|ac|no\\.|bal|balance)[\\s:.]*$value',
      caseSensitive: false,
    );
    if (!beforePattern.hasMatch(content)) {
      return value;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// extractAmount
// ---------------------------------------------------------------------------

double? extractAmount(String content) {
  // EPFO passbook SMS state both a passbook balance and a contribution
  // amount in the same message ("your passbook balance ... is Rs.
  // 1,75,975/-. Contribution of Rs. 2,350/- ... has been received.") — the
  // generic first-Rs.-match scan below would grab the balance (mentioned
  // first, and typically the larger figure) instead of the contribution
  // that's actually this transaction's amount. Checked ahead of the
  // generic patterns so "contribution of Rs. X" phrasing always wins
  // whenever both appear together, regardless of which comes first.
  final contributionMatch =
      RegExp(r'contribution\s+of\s+(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false)
          .firstMatch(content);
  final contributionRaw = contributionMatch?.group(1);
  if (contributionRaw != null) {
    final contributionAmount = double.tryParse(contributionRaw.replaceAll(',', ''));
    if (contributionAmount != null && contributionAmount > 0) return contributionAmount;
  }

  final patterns = [
    RegExp(r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false),
    RegExp(r'([\d,]+(?:\.\d{1,2})?)\s*(?:rs|rupees|inr)', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    for (final match in pattern.allMatches(content)) {
      final group1 = match.group(1);
      if (group1 == null) continue;
      final amount = double.tryParse(group1.replaceAll(',', ''));
      if (amount == null || amount <= 0 || amount >= 10000000) continue;

      if (amount >= 1900 &&
          amount <= 2100 &&
          !content.toLowerCase().contains('rs') &&
          !content.contains('₹')) {
        continue; // Likely a year
      }
      return amount;
    }
  }

  // Special handling for Pluxee/Sodexo which often omits the currency symbol.
  if (RegExp(r'Pluxee|Sodexo', caseSensitive: false).hasMatch(content)) {
    final pluxeeMatch = RegExp(r'with\s+([\d,]+(?:\.\d{1,2})?)\s+towards', caseSensitive: false)
            .firstMatch(content) ??
        RegExp(r'purchase\s+of\s+([\d,]+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(content);
    final group1 = pluxeeMatch?.group(1);
    if (group1 != null) {
      return double.tryParse(group1.replaceAll(',', ''));
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// extractMerchant
// ---------------------------------------------------------------------------

String? extractMerchant(String content) {
  final merchantPatterns = [
    RegExp(r'([a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+)'), // UPI VPA
    // Many bank SMS are laid out as separate newline-delimited fields
    // ("Sent Rs.X\nFrom HDFC Bank A/C *6020\nTo MERCHANT\nOn date\n...")
    // rather than one sentence, so the payee sits alone on its own "To "
    // line — never adjacent to "paid"/"sent"/"transfer" the way the
    // sentence-style patterns below expect.
    RegExp(r"(?:^|\n)To\s+([A-Za-z0-9\s&./'-]{2,50}?)\s*(?:\n|$)", caseSensitive: false),
    // "...deducted from HDFC Bank A/C No 6020 towards PayTM Money UMRN:
    // ..." / "...bill of Rs.X against BSDIRECT-F18152 ..." — stops at a
    // slash or "UMRN" since those introduce a reference code, not more of
    // the payee name.
    RegExp(r"towards\s+([A-Za-z0-9\s&.'-]{2,40}?)(?:\s*\/|\s+UMRN|\n|$|\.)", caseSensitive: false),
    RegExp(
      r"(?:paid\s+to|sent\s+to|transfer\s+to|at)\s+([A-Za-z0-9\s&.*_/'-]{2,30}?)(?:\s+(?:via|using|through|on|by)|$|\.|\n)",
      caseSensitive: false,
    ),
    RegExp(
      r"(?:received\s+from|credit\s+from)\s+([A-Za-z0-9\s&.'-]{2,30}?)(?:\s+(?:via|using|through|on|by)|$|\.)",
      caseSensitive: false,
    ),
    RegExp(
      r"(?:spent\s+at|used\s+at|purchase\s+at)\s+([A-Za-z0-9\s&.'-]{2,30}?)(?:\s+on|$|\.)",
      caseSensitive: false,
    ),
    // "Bill Paid: AxisMF Bill AXDIRECT-F18152 of Rs.X ... via SmartPay" —
    // AMC/biller bill-pay confirmations name the biller right after "Bill
    // Paid:" and again before "Bill <reference>".
    RegExp(r'Bill\s+Paid[:!]?\s*\n?\s*([A-Za-z0-9]+)\s+Bill\b', caseSensitive: false),
    // "UPDATE: Your Axis Mutual Fund bill payment of Rs.X for ... has been
    // processed successfully." — the AMC name sits between "Your" and
    // "bill payment".
    RegExp(r'Your\s+([A-Za-z0-9\s]+?)\s+bill\s+payment', caseSensitive: false),
    // "Money Transfer:Rs X from HDFC Bank A/c **6020 on date to MERCHANT
    // UPI: ..." — HDFC's IMPS/UPI transfer-confirmation format.
    RegExp(r"\bto\s+([A-Za-z0-9\s&.\-]{2,40}?)\s+UPI\b", caseSensitive: false),
    // "Payment of Rs.X to MERCHANT succeeded." — payment-gateway
    // confirmations (PayU/aggregators).
    RegExp(r'\bto\s+([A-Za-z0-9_.\s&-]{2,40}?)\s+succeeded\b', caseSensitive: false),
    // "Transaction of Rs.900.00 for purchase of Petrol is successful." —
    // HP Pay fuel-purchase confirmations; the category name stands in for
    // a specific business name here.
    RegExp(r'for\s+purchase\s+of\s+([A-Za-z\s]+?)\s+is\b', caseSensitive: false),
  ];

  const excludeList = [
    'your', 'the', 'account', 'card', 'bank', 'ac', 'a/c', 'ending', 'nav', 'folio', 'units', 'rs', 'inr',
  ];

  for (final pattern in merchantPatterns) {
    final match = pattern.firstMatch(content);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;

    final merchant = raw.replaceAll(RegExp(r'\s+via\s+upi', caseSensitive: false), '');
    if (merchant.isEmpty) continue;

    final merchantLower = merchant.toLowerCase();
    if (!excludeList.any((word) => merchantLower.startsWith(word))) {
      return merchant[0].toUpperCase() + merchant.substring(1);
    }
  }

  const commonMerchants = [
    'swiggy', 'zomato', 'uber', 'ola', 'amazon', 'flipkart', 'myntra', 'netflix',
    'spotify', 'hotstar', 'jiomart', 'bigbasket', 'blinkit', 'zepto', 'bookmyshow', 'makemytrip',
  ];
  final contentLower = content.toLowerCase();
  for (final m in commonMerchants) {
    if (contentLower.contains(m)) {
      return m[0].toUpperCase() + m.substring(1);
    }
  }

  if (RegExp(r'Pluxee|Sodexo', caseSensitive: false).hasMatch(content)) return 'Pluxee';

  return null;
}

// ---------------------------------------------------------------------------
// extractAccountNumber
// ---------------------------------------------------------------------------

String? extractAccountNumber(String content) {
  final explicitPatterns = [
    // EPFO passbook SMS: "your passbook balance against KRMAL...0085 is
    // Rs. X." — the establishment+member code after "against" is the
    // actual PF account reference. Checked first: a masked number earlier
    // in the same message (e.g. "Dear XXXXXXXX1745,", the user's own
    // masked UAN/mobile prefix) would otherwise win via the generic
    // mask-scan below just by appearing first in the text, even though
    // it isn't the scheme-account identifier.
    RegExp(r'balance\s+against\s+\S*?(\d{4})\b', caseSensitive: false),
    // Mask length varies by bank — some use a single "*" ("A/C *6020"),
    // others "XX"/"xxxx"/multiple asterisks. Widened from requiring 2+
    // mask characters to 1+ so a lone "*" or "x" still matches.
    RegExp(
      r'(?:bank|a\/c|acct|account|card)\s*(?:no\.?|ending(?:\s+with)?|xxxx?)?\s*[:\s.-]*(?:xx|x{1,4}|\*{1,4})(\d{4})',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:debited from|credited to|debited\s+from|credited\s+to)\s+(?:.*?)\s+(?:xx|x{1,4}|\*{1,4})(\d{4})',
      caseSensitive: false,
    ),
    RegExp(r'(?:SB|SA|CA)[-.\s]*(?:xx|x{1,4}|\*{1,4})[-\s]*(\d{4})', caseSensitive: false),
    // "card ending 1009" / "...ending with 6408" — some card-payment
    // alerts state the last 4 digits directly after "ending" with no
    // xx/*/x mask at all.
    RegExp(r'card\s+ending(?:\s+with)?\s+(\d{4})\b', caseSensitive: false),
  ];

  for (final pattern in explicitPatterns) {
    final match = pattern.firstMatch(content);
    final digits = match?.group(1);
    if (digits != null) return 'XX$digits';
  }

  // Remove UPI reference / ref-no patterns before the generic XX pass, so
  // they don't get mistaken for a masked account number.
  var safeContent = content.replaceAll(
    RegExp(r'UPI-[a-zA-Z0-9-]+\d{4}', caseSensitive: false),
    'UPI-REFERENCE-REMOVED',
  );
  safeContent = safeContent.replaceAll(
    RegExp(r'Ref\s*no\s*\d+', caseSensitive: false),
    'REF-REMOVED',
  );

  final genericMatch =
      RegExp(r'(?:xx|x{1,}|\*{1,})[-\s]*(\d{4})', caseSensitive: false).firstMatch(safeContent);
  final genericDigits = genericMatch?.group(1);
  if (genericDigits != null) return 'XX$genericDigits';

  // Last resort: some SMS state the account/card's last 4 digits fully
  // bare, with no xx/*/x mask at all (e.g. "HDFC Bank A/C No 6020",
  // "from HDFC Bank A/c 6020", "HDFC Bank Card 6408"). Only reached once
  // every masked pattern above has failed, and requires the digits to sit
  // immediately next to the a/c or card keyword with a hard word
  // boundary, so it can't grab an unrelated 4-digit number (a year, part
  // of a longer number, ...) elsewhere in the message.
  final bareMatch = RegExp(
    r'(?:a\/c|acct|account)\s*(?:no\.?)?\s+(\d{4})\b|\bcard\s+(\d{4})\b',
    caseSensitive: false,
  ).firstMatch(safeContent);
  if (bareMatch != null) {
    final digits = bareMatch.group(1) ?? bareMatch.group(2);
    if (digits != null) return 'XX$digits';
  }

  if (RegExp(r'Pluxee|Sodexo', caseSensitive: false).hasMatch(content) &&
      (content.contains('Card') || content.contains('card'))) {
    return 'Pluxee Card';
  }

  return null;
}

// ---------------------------------------------------------------------------
// extractBalance
// ---------------------------------------------------------------------------

double? extractBalance(String content) {
  final balancePatterns = [
    // EPFO passbook SMS: "your passbook balance against KRMAL...0085 is
    // Rs. 1,75,975/-." — the account reference sits between "balance" and
    // the actual Rs. figure, which the generic "balance ... Rs. X" pattern
    // below can't bridge (its `[:;\s-]*` gap doesn't allow the letters/
    // digits/asterisks of an account number in between). Checked first so
    // it wins over the generic pattern for this specific phrasing.
    RegExp(
      r'passbook\s+balance\s+against\s+.*?\s+is\s+(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:avl\.?\s*bal\.?|available\s+balance|bal\.?|balance)[:;\s-]*(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:wallet|fuel|meal|gift)\s+(?:wallet\s+)?balance\s+(?:is|are)\s+(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ),
    RegExp(
      r'wallet\s+balance\s*[:;\s-]*(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ),
  ];

  for (final pattern in balancePatterns) {
    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) continue;
    final group1 = matches.last.group(1); // most recent balance mention wins
    if (group1 != null) {
      final amount = double.tryParse(group1.replaceAll(',', ''));
      if (amount != null) return amount;
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// getTransactionType
// ---------------------------------------------------------------------------

enum ParsedDirection { credit, debit, reversal, unknown }

ParsedDirection getTransactionType(String content) {
  final contentLower = content.toLowerCase();

  if (contentLower.contains('reversed') ||
      contentLower.contains('declined') ||
      contentLower.contains('failed') ||
      contentLower.contains('trxn reversed')) {
    return ParsedDirection.reversal;
  }

  // Investment debit, high priority: "units allotted"/"SIP processed with
  // NAV" mean money LEFT the user's bank account even though the message
  // says "credited" (to the fund/folio, not to the user's cash).
  if ((contentLower.contains('allotted') || contentLower.contains('alloted')) ||
      (contentLower.contains('sip') &&
          contentLower.contains('processed') &&
          contentLower.contains('nav')) ||
      (contentLower.contains('units') && contentLower.contains('credited'))) {
    return ParsedDirection.debit;
  }

  // Self-transfer into a PPF/SSY (Sukanya Samriddhi) sub-account: "Rs.X
  // transferred to your PPF/SSY A/c No. ..." reads like an incoming
  // transfer ("to your ... A/c") but is really money leaving the linked
  // bank account into a locked scheme, so it needs to be called out ahead
  // of the generic "credited"/"received" check below.
  if (contentLower.contains('transferred') &&
      (contentLower.contains('ppf') ||
          contentLower.contains('ssy') ||
          contentLower.contains('sukanya samriddhi'))) {
    return ParsedDirection.debit;
  }

  // "HDFC Bank : NEFT money transfer ... has been credited to <Recipient
  // Name> on ..." — an outgoing NEFT/IMPS confirmation phrased from the
  // *recipient's* side ("credited to Priya Sharma"), not the user's own
  // account ("credited to a/c ..." / "credited to your wallet") — this is
  // really a debit from the sender's perspective despite containing
  // "credited". Narrowly scoped to NEFT/IMPS/money-transfer wording so it
  // can't misfire on the far more common "credited to a/c XX6020" /
  // "credited to your ..." self-account phrasing, which stays a credit.
  if (RegExp(r'credited\s+to\s+(?!your\b|a\/c|account)[A-Za-z]', caseSensitive: false)
          .hasMatch(content) &&
      RegExp(r'\b(neft|imps|money\s+transfer)\b', caseSensitive: false).hasMatch(content)) {
    return ParsedDirection.debit;
  }

  if (contentLower.contains('credited') ||
      contentLower.contains('received') ||
      contentLower.contains('deposited') ||
      contentLower.contains('added to') ||
      // "you have successfully added Rs.X into your Securities account" —
      // a broker/trading-app funds-added confirmation, same shape as
      // "added to" but without the trailing "to".
      contentLower.contains('successfully added') ||
      contentLower.contains('refund on') ||
      contentLower.contains('refund processed') ||
      contentLower.contains('redemption') ||
      contentLower.contains('redeemed')) {
    return ParsedDirection.credit;
  }

  // Exclude "due"/"bill" reminders that haven't actually been paid yet.
  if (contentLower.contains('due') ||
      contentLower.contains('bill generated') ||
      contentLower.contains('to be paid')) {
    if (!contentLower.contains('paid') &&
        !contentLower.contains('debited') &&
        !contentLower.contains('auto-debited')) {
      return ParsedDirection.unknown;
    }
  }

  if (contentLower.contains('debited') ||
      contentLower.contains('deducted') ||
      contentLower.contains('spent') ||
      contentLower.contains('paid') ||
      contentLower.contains('withdrawn') ||
      contentLower.contains('purchase') ||
      contentLower.contains('switch in') ||
      contentLower.contains('sent to') ||
      contentLower.contains('transfer to') ||
      contentLower.contains('installment') ||
      contentLower.contains('allotted') ||
      // Payment-gateway confirmations ("Payment of Rs.X to Y succeeded",
      // "Transaction No. N for Rs X ... has succeeded") and AMC bill-pay
      // alerts ("Your Axis Mutual Fund bill payment of Rs.X ... has been
      // processed successfully") never use "debited"/"paid" wording at
      // all, but both only ever describe money that left the account —
      // credit-side messages ("redeemed", "credited", ...) already
      // returned above, so these can't collide with a real credit.
      contentLower.contains('succeeded') ||
      contentLower.contains('processed successfully') ||
      // "Money Transfer:Rs X from HDFC Bank A/c ... to Y" — HDFC's IMPS
      // confirmation format, always outgoing.
      contentLower.contains('money transfer')) {
    return ParsedDirection.debit;
  }

  // HDFC's newer "Sent Rs.X\nFrom ... A/C ...\nTo ...\n" UPI confirmation
  // format never uses "sent to" as one phrase (the "To" is its own line),
  // so the "sent to" check above misses it; word-bounded so it doesn't
  // fire on unrelated words like "consent". Always a debit — nothing in
  // this bank's SMS vocabulary uses bare "sent" for money coming in.
  if (RegExp(r'\bsent\b', caseSensitive: false).hasMatch(content)) {
    return ParsedDirection.debit;
  }

  return ParsedDirection.unknown;
}

// ---------------------------------------------------------------------------
// extractBankName / extractBankNameFromContent
// ---------------------------------------------------------------------------

const Map<String, String> _bankNamesBySenderKeyword = {
  'HDFC': 'HDFC Bank',
  'ICICI': 'ICICI Bank',
  'SBI': 'SBI',
  'AXIS': 'Axis Bank',
  'KOTAK': 'Kotak Bank',
  'PNB': 'PNB',
  'BOB': 'Bank of Baroda',
  'CANARA': 'Canara Bank',
  'PAYTM': 'Paytm Bank',
  // "PYTMBK" is Paytm Payments Bank's other real-world DLT sender code —
  // doesn't contain "PAYTM" as a substring, so needs its own entry.
  'PYTMBK': 'Paytm Bank',
  'PHONE': 'PhonePe',
  'GPAY': 'Google Pay',
  'GOOG': 'Google Pay',
  'BHIM': 'BHIM UPI',
  'UNION': 'Union Bank',
  'INDUS': 'IndusInd Bank',
  'RBL': 'RBL Bank',
  'IDFC': 'IDFC First Bank',
  'YES': 'Yes Bank',
  'IOB': 'Indian Overseas Bank',
  'AIRBNK': 'Airtel Payments Bank',
  'ZERODH': 'Zerodha',
  // Zerodha's actual DLT sender ID ("ZRODHA") drops the "E" — doesn't
  // contain "ZERODH", so needs its own entry alongside it.
  'ZRODHA': 'Zerodha',
  'GROWW': 'Groww',
  'INDMON': 'IndMoney',
  'KUVERA': 'Kuvera',
  'UPSTOX': 'Upstox',
};

/// Note: the source file's getSenderName() CSV-lookup indirection is a
/// permanent stub there (removed for performance, per its own comment) —
/// skipped here rather than ported as dead code.
String? extractBankName(String sender) {
  final senderUpper = sender.toUpperCase();
  for (final entry in _bankNamesBySenderKeyword.entries) {
    if (senderUpper.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Fallback for gift cards etc. that come from a generic sender (e.g. a
/// Flipkart gift card notification sent from a shortcode, not "FLPKRT").
String? extractBankNameFromContent(String content) {
  final match = RegExp(r'([A-Za-z]+)\s+Gift\s+Card', caseSensitive: false).firstMatch(content);
  final brand = match?.group(1);
  if (brand != null) {
    const generics = ['my', 'your', 'the', 'a', 'an', 'new', 'free'];
    if (!generics.contains(brand.toLowerCase())) {
      return brand[0].toUpperCase() + brand.substring(1);
    }
  }

  // EPFO passbook SMS don't always name "EPFO"/"Provident Fund" in the
  // sender ID the way a bank's DLT header would — "passbook balance" is
  // the one consistently EPFO-specific phrase available, so it's used
  // here rather than in _bankNamesBySenderKeyword above.
  if (RegExp(r'\bepfo\b|provident fund|passbook balance', caseSensitive: false).hasMatch(content)) {
    return 'EPFO';
  }

  return null;
}

// ---------------------------------------------------------------------------
// extractEntityType
// ---------------------------------------------------------------------------

enum ParsedEntityType { bank, wallet, investment, cardService, unknown }

ParsedEntityType extractEntityType(String sender, String content) {
  final senderUpper = sender.toUpperCase();
  final contentLower = content.toLowerCase();

  const walletProviders = [
    'PAYTM', 'PYTM', 'PHONEPE', 'PHONE-PE', 'GPAY', 'GOOGLEPAY', 'GOOG',
    'AMAZONPAY', 'AMZNPAY', 'PLUXEE', 'SODEXO', 'MOBIKWIK', 'FREECHARGE',
    'OLAMONEY', 'DHANI', 'AIRTEL-PAY', 'AIRTELBANK', 'JIOMONEY',
  ];
  for (final wallet in walletProviders) {
    if (senderUpper.contains(wallet)) return ParsedEntityType.wallet;
  }

  if (senderUpper.contains('FASTAG') || contentLower.contains('fastag')) {
    return ParsedEntityType.wallet;
  }

  if (contentLower.contains('wallet balance') ||
      contentLower.contains('paytm wallet') ||
      contentLower.contains('phonepe wallet') ||
      contentLower.contains('meal wallet') ||
      contentLower.contains('fuel wallet') ||
      contentLower.contains('gift wallet') ||
      (contentLower.contains('office wear') &&
          (contentLower.contains('pluxee') || contentLower.contains('sodexo'))) ||
      contentLower.contains('pluxee') ||
      contentLower.contains('sodexo')) {
    return ParsedEntityType.wallet;
  }

  const investmentProviders = [
    'ZERODHA', 'ZERODH', 'ZRODHA', 'GROWW', 'KUVERA', 'INDMONEY', 'INDMON',
    'UPSTOX', 'ANGEL', 'ANGELONE', 'SHAREKHAN', 'MOTILAL', 'IIFL',
    'ICICI-PRU', 'ICICIPRU', 'IPRUMF', 'HDFC-MF', 'SBI-MF', 'AXIS-MF',
    'ABCAMC', 'MIRAEI', 'NIPPON', 'KOTAK-MF', 'DSP-MF', 'UTI-MF',
    'QNTAMC', 'BOIAMC', 'EPFO',
  ];
  for (final investment in investmentProviders) {
    if (senderUpper.contains(investment)) return ParsedEntityType.investment;
  }

  // EPFO passbook SMS ("your passbook balance against KRMAL...0085 is
  // Rs. X. Contribution of Rs. Y ... has been received.") don't always
  // name "EPFO" in the sender ID the way a bank's DLT header does —
  // "passbook balance" is the one consistently EPFO-specific phrase
  // available, so it's checked by content here too, not just sender.
  if (contentLower.contains('epfo') ||
      contentLower.contains('provident fund') ||
      contentLower.contains('passbook balance')) {
    return ParsedEntityType.investment;
  }

  if ((senderUpper.contains('MF') ||
          senderUpper.contains('AMC') ||
          senderUpper.contains('MUTUAL') ||
          senderUpper.contains('FUND')) &&
      (contentLower.contains('sip') ||
          contentLower.contains('nav') ||
          contentLower.contains('folio') ||
          contentLower.contains('units') ||
          contentLower.contains('allotted') ||
          contentLower.contains('redemption'))) {
    return ParsedEntityType.investment;
  }

  if (contentLower.contains('nps') &&
      (contentLower.contains('tier 1') ||
          contentLower.contains('tier i') ||
          contentLower.contains('tier 2') ||
          contentLower.contains('tier ii'))) {
    return ParsedEntityType.investment;
  }

  if (contentLower.contains('sip') &&
      (contentLower.contains('processed') ||
          contentLower.contains('due') ||
          contentLower.contains('installment'))) {
    return ParsedEntityType.investment;
  }
  if (contentLower.contains('folio') ||
      (contentLower.contains('units') && contentLower.contains('nav'))) {
    return ParsedEntityType.investment;
  }

  const cardNetworks = ['VISA', 'MASTER', 'RUPAY', 'AMEX', 'DINERS'];
  for (final network in cardNetworks) {
    if (senderUpper.contains(network)) return ParsedEntityType.cardService;
  }

  if (contentLower.contains('cardmember')) return ParsedEntityType.cardService;

  if (contentLower.contains('credited to your card') || contentLower.contains('credited to card')) {
    return ParsedEntityType.cardService;
  }

  if (contentLower.contains('card') &&
      (contentLower.contains('spent') ||
          contentLower.contains('used at') ||
          contentLower.contains('card ending') ||
          (contentLower.contains('payment') && contentLower.contains('card')))) {
    if (RegExp(r'card.*(?:ending|xxxx|xx\d{4})', caseSensitive: false).hasMatch(contentLower) ||
        contentLower.contains('outstanding')) {
      return ParsedEntityType.cardService;
    }
  }

  const bankKeywords = [
    'BANK', 'HDFC', 'ICICI', 'SBI', 'AXIS', 'KOTAK', 'PNB', 'BOB',
    'CANARA', 'UNION', 'INDUS', 'RBL', 'IDFC', 'YES', 'FEDERAL', 'KARUR', 'IOB',
    'AIRBNK',
  ];
  for (final bank in bankKeywords) {
    if (senderUpper.contains(bank) &&
        !senderUpper.contains('MF') &&
        !senderUpper.contains('WALLET') &&
        !senderUpper.contains('PAY')) {
      return ParsedEntityType.bank;
    }
  }

  return ParsedEntityType.unknown;
}

// ---------------------------------------------------------------------------
// extractBillDueDate
// ---------------------------------------------------------------------------

DateTime? extractBillDueDate(String content) {
  final dueDatePatterns = [
    RegExp(
      r'(?:due\s+date|payment\s+due|valid\s+until)[:\s]*(\d{1,2}[-/\s][A-Za-z]{3,}[-/\s]\d{2,4})',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:due\s+date|payment\s+due|valid\s+until)[:\s]*(\d{1,2}[-/\s]\d{1,2}[-/\s]\d{2,4})',
      caseSensitive: false,
    ),
  ];

  for (final pattern in dueDatePatterns) {
    final raw = pattern.firstMatch(content)?.group(1);
    if (raw == null) continue;
    final parsed = tryParseFlexibleDate(raw);
    if (parsed != null) return parsed;
  }
  return null;
}

/// Dart's DateTime.parse only accepts ISO-8601, unlike JS's lenient
/// `new Date(str)` which happily parses "18-Feb-25" or "05/03/2024". This
/// is a small hand-written stand-in covering the two formats
/// [extractBillDueDate] actually produces: "DD-MMM-YY(YY)" and
/// "DD-MM-YYYY"/"DD/MM/YYYY"/"DD.MM.YYYY" (day-first, matching Indian SMS
/// conventions — also reused by [extractInvestmentValueStatement] for
/// "as on DD.MM.YY" statement dates, which favour dots over slashes).
DateTime? tryParseFlexibleDate(String raw) {
  final normalized = raw.trim();

  final monthNameMatch =
      RegExp(r'^(\d{1,2})[-/\s]([A-Za-z]{3,})[-/\s](\d{2,4})$').firstMatch(normalized);
  if (monthNameMatch != null) {
    final day = int.tryParse(monthNameMatch.group(1)!);
    final month = _monthFromName(monthNameMatch.group(2)!);
    final year = _normalizeYear(monthNameMatch.group(3)!);
    if (day != null && month != null) {
      return _safeDate(year, month, day);
    }
  }

  final numericMatch = RegExp(r'^(\d{1,2})[-/.\s](\d{1,2})[-/.\s](\d{2,4})$').firstMatch(normalized);
  if (numericMatch != null) {
    final day = int.tryParse(numericMatch.group(1)!);
    final month = int.tryParse(numericMatch.group(2)!);
    final year = _normalizeYear(numericMatch.group(3)!);
    if (day != null && month != null && month >= 1 && month <= 12) {
      return _safeDate(year, month, day);
    }
  }

  return null;
}

DateTime? _safeDate(int year, int month, int day) {
  try {
    final date = DateTime(year, month, day);
    // DateTime silently rolls over invalid days (e.g. Feb 31 -> Mar 3) rather
    // than throwing, so double check it round-trips to what was asked for.
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  } catch (_) {
    return null;
  }
}

int _normalizeYear(String raw) {
  final year = int.parse(raw);
  return year < 100 ? 2000 + year : year;
}

const Map<String, int> _monthNames = {
  'jan': 1, 'january': 1,
  'feb': 2, 'february': 2,
  'mar': 3, 'march': 3,
  'apr': 4, 'april': 4,
  'may': 5,
  'jun': 6, 'june': 6,
  'jul': 7, 'july': 7,
  'aug': 8, 'august': 8,
  'sep': 9, 'sept': 9, 'september': 9,
  'oct': 10, 'october': 10,
  'nov': 11, 'november': 11,
  'dec': 12, 'december': 12,
};

int? _monthFromName(String name) {
  final lower = name.toLowerCase();
  if (_monthNames.containsKey(lower)) return _monthNames[lower];
  final abbrev = lower.length >= 3 ? lower.substring(0, 3) : lower;
  return _monthNames[abbrev];
}

// ---------------------------------------------------------------------------
// extractWalletType
// ---------------------------------------------------------------------------

String? extractWalletType(String content, String sender) {
  final senderUpper = sender.toUpperCase();
  final contentLower = content.toLowerCase();

  final isFastag = senderUpper.contains('FASTAG') ||
      contentLower.contains('fastag') ||
      (contentLower.contains('toll') && contentLower.contains('paid'));

  if (isFastag) {
    final senderBankMatch =
        RegExp(r'HDFC|ICICI|PAYTM|AXIS|SBI|KOTAK', caseSensitive: false).firstMatch(sender);
    if (senderBankMatch != null) return '${senderBankMatch.group(0)} FASTag';

    final fastagMatch =
        RegExp(r'(HDFC|ICICI|Paytm|Axis|SBI|Kotak).*(?:FASTag|Toll)', caseSensitive: false)
            .firstMatch(content);
    if (fastagMatch != null) return '${fastagMatch.group(1)} FASTag';

    return 'FASTag Wallet';
  }

  if (senderUpper.contains('PAYTM') && !senderUpper.contains('BANK')) return 'Paytm Wallet';
  if (senderUpper.contains('PHONEPE') || senderUpper.contains('PHONE-PE')) return 'PhonePe Wallet';
  if (senderUpper.contains('GPAY') || senderUpper.contains('GOOGLEPAY')) return 'Google Pay';
  if (senderUpper.contains('AMAZONPAY') || senderUpper.contains('AMZNPAY')) return 'Amazon Pay';
  if (senderUpper.contains('MOBIKWIK')) return 'MobiKwik Wallet';
  if (senderUpper.contains('FREECHARGE')) return 'Freecharge Wallet';
  if (senderUpper.contains('OLAMONEY')) return 'Ola Money';
  if (senderUpper.contains('DHANI')) return 'Dhani Wallet';

  final pluxeeSodexo = RegExp(r'Pluxee|Sodexo', caseSensitive: false);
  if (pluxeeSodexo.hasMatch(content) || pluxeeSodexo.hasMatch(sender)) {
    if (RegExp(r'reimbursement\s+wallet', caseSensitive: false).hasMatch(content)) {
      return 'Reimbursement Wallet';
    }

    final claimMatch =
        RegExp(r'against\s+your\s+([A-Za-z\s&]+?)\s+reimbursement\s+claim', caseSensitive: false)
            .firstMatch(content);
    if (claimMatch?.group(1) != null) return '${claimMatch!.group(1)!.trim()} Wallet';

    final towardsMatch =
        RegExp(r'towards\s+([A-Za-z\s&]+?)(?:\s+on|\s+Wallet|\.|$)', caseSensitive: false)
            .firstMatch(content);
    if (towardsMatch?.group(1) != null) {
      final matchText = towardsMatch!.group(1)!.trim();
      if (matchText.toLowerCase() == 'online convenience fee') return 'Pluxee Wallet';
      return '$matchText Wallet';
    }

    if (contentLower.contains('fuel')) return 'Fuel Wallet';
    if (contentLower.contains('meal') || contentLower.contains('food')) return 'Meal Wallet';
    if (contentLower.contains('office wear') || contentLower.contains('apparel')) {
      return 'Office Wear Wallet';
    }
    if (contentLower.contains('telecom') ||
        contentLower.contains('telecommunication') ||
        contentLower.contains('data')) {
      return 'Telecom & Data Wallet';
    }

    return 'Pluxee Wallet';
  }

  final walletPatterns = [
    RegExp(r'fuel\s+wallet', caseSensitive: false),
    RegExp(r'meal\s+wallet', caseSensitive: false),
    RegExp(r'food\s+wallet', caseSensitive: false),
    RegExp(r'office\s+wear', caseSensitive: false),
    RegExp(r'gift\s+wallet', caseSensitive: false),
    RegExp(r'paytm\s+wallet', caseSensitive: false),
    RegExp(r'amazon\s+pay(?:\s+balance)?', caseSensitive: false),
    RegExp(r'ola\s+money', caseSensitive: false),
    RegExp(r'phonepe\s+wallet', caseSensitive: false),
    RegExp(r'mobikwik', caseSensitive: false),
    RegExp(r'freecharge', caseSensitive: false),
    RegExp(r'dhani', caseSensitive: false),
    RegExp(r'(?:un)?billed\s+wallet', caseSensitive: false),
    RegExp(r'wallet\s+balance', caseSensitive: false),
    RegExp(r'(?:added|sent|paid)\s+to\s+(?:your\s+)?(.+?)\s+wallet', caseSensitive: false),
  ];
  for (final pattern in walletPatterns) {
    final match = pattern.firstMatch(content);
    if (match != null) return _capitalizeWords(match.group(0)!);
  }

  final genericMatch = RegExp(r'([a-zA-Z]{2,})\s+wallet', caseSensitive: false).firstMatch(content);
  if (genericMatch?.group(1) != null) {
    final name = genericMatch!.group(1)!.trim();
    const excludeWords = [
      'your', 'my', 'the', 'reach', 'to', 'from', 'in', 'on', 'total', 'updated', 'bal', 'wallet',
    ];
    if (!excludeWords.contains(name.toLowerCase())) {
      return '${name[0].toUpperCase()}${name.substring(1)} Wallet';
    }
  }

  return null;
}

String _capitalizeWords(String input) =>
    input.replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

// ---------------------------------------------------------------------------
// extractInvestmentDetails
// ---------------------------------------------------------------------------

class ExtractedInvestmentDetails {
  String? investmentName;

  /// This *installment's own* unit count (e.g. "155.248 units ... have
  /// been allotted") — a delta to add to a holding's running total, not
  /// the total itself. Mutually exclusive with [balanceUnits]; see there.
  double? units;

  /// A stated running/cumulative unit balance (e.g. "Balance Units
  /// 205.177") — the folio's total units *after* this transaction, not
  /// this installment's own allotment. Kept separate from [units]
  /// specifically so callers never accidentally sum it across installments
  /// the way a real per-installment delta should be summed.
  double? balanceUnits;

  double? nav;
  String? folio;
  String? amc;
}

ExtractedInvestmentDetails extractInvestmentDetails(String content, String sender) {
  final details = ExtractedInvestmentDetails();

  final folioMatch =
      RegExp(r'(?:folio|fol)\s*(?:no\.?|number|id)?\s*[:\-\/]?\s*([0-9A-Z\/]+)', caseSensitive: false)
          .firstMatch(content);
  if (folioMatch?.group(1) != null) {
    details.folio = folioMatch!.group(1);
  } else {
    final pranMatch = RegExp(r'PRAN\s*[:\-]?\s*([X\d]+)', caseSensitive: false).firstMatch(content);
    if (pranMatch?.group(1) != null) details.folio = pranMatch!.group(1);
  }

  // The negative lookahead rejects "NAV of 04/04/25" (an *allotment date*,
  // e.g. Protean/NPS "Units ... credited with NAV of 04/04/25") before the
  // digit capture ever runs — without it, `[0-9,]+` greedily grabs "04",
  // stops at the "/", and happily parses that lone "04" as NAV=4, wildly
  // corrupting units-derivation (amount ÷ NAV) and every downstream
  // NAV/value chart. It has to sit *before* the capture group, not as a
  // lookahead immediately after it — placing it after is defeated by
  // backtracking, since the engine just shrinks `[0-9,]+` to "0" (still not
  // followed by "/") and "succeeds" with an equally bogus NAV=0.
  final navMatch = RegExp(
    r'NAV\s*(?:of|is)?\s*[:\-]?\s*(?:Rs\.?)?\s*(?!\d{1,2}\/\d{1,2}\/\d{2,4}\b)([0-9,]+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(content);
  if (navMatch?.group(1) != null) {
    details.nav = double.tryParse(navMatch!.group(1)!.replaceAll(',', ''));
  }

  if (content.contains('PRAN') || RegExp(r'NPS', caseSensitive: false).hasMatch(sender)) {
    details.investmentName ??= 'NPS Scheme';
    details.amc = 'NPS';
  }

  // "Balance Units X" (common in AMC purchase/SIP confirmations, e.g.
  // ABSL MF's "... is processed. Balance Units 205.177.") states the
  // folio's *running total* after this transaction, not this installment's
  // own allotment — checked first and, when it matches, deliberately skips
  // the generic `unitsMatch` fallback below (which would otherwise also
  // match the same "Units 205.177" text and misfile it as a delta). Mixing
  // the two up meant every installment's *cumulative* balance got summed
  // as if each one were a fresh allotment on top of the last — a 205-unit
  // balance followed by a 212-unit balance next month was being recorded
  // as ~417 units held, not the ~212 the statement actually reported.
  final balanceUnitsMatch =
      RegExp(r'balance\s+units\s*[:\-]?\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(content);
  if (balanceUnitsMatch?.group(1) != null) {
    details.balanceUnits = double.tryParse(balanceUnitsMatch!.group(1)!.replaceAll(',', ''));
  } else {
    final unitsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*units', caseSensitive: false).firstMatch(content) ??
        RegExp(r'units\s*[:\-]?\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(content);
    if (unitsMatch?.group(1) != null) {
      details.units = double.tryParse(unitsMatch!.group(1)!.replaceAll(',', ''));
    }
  }

  final contentLower = content.toLowerCase();
  // Word-boundary matching matters here: a plain `.contains('tier i')`
  // check is also a substring match against "tier ii" ("tier i" is
  // literally the first 6 characters of "tier ii"), so the Tier 1 branch
  // used to fire for *every* Tier II message too — and since it was
  // checked first, Tier II never actually got a chance to be detected.
  // `\b` after the numeral requires a non-word character (or end of
  // string) right after it, which the second "i" in "ii" isn't, so this
  // correctly stops "tier i" from matching inside "tier ii".
  final isTier1 = RegExp(r'\btier\s+(?:1|i)\b').hasMatch(contentLower);
  final isTier2 = RegExp(r'\btier\s+(?:2|ii)\b').hasMatch(contentLower);
  if (contentLower.contains('nps') && isTier2) {
    details.investmentName = 'NPS Tier 2';
    details.amc = 'NPS';
  } else if (contentLower.contains('nps') && isTier1) {
    details.investmentName = 'NPS Tier 1';
    details.amc = 'NPS';
  }

  final fundPatterns = [
    RegExp(
      r'in\s+(?:your\s+)?Folio[\s\-]+[0-9A-Z\/]+\s+under\s+([A-Za-z0-9\s\-_&()]+) (?:for|with)',
      caseSensitive: false,
    ),
    RegExp(
      r'in\s+(?:your\s+)?Folio\s+[0-9A-Z\/]+\s+in\s+([A-Za-z0-9\s\-_&()]+?)(?:\s+(?:has been|is|processed|for|units)|$)',
      caseSensitive: false,
    ),
    RegExp(
      r'towards\s+(?:your\s+)?(?:SIP|investment)\s+in\s+([A-Za-z0-9\s\-_&()]+?)(?:\s+(?:has been|is|processed)|,|\s+dated|$)',
      caseSensitive: false,
    ),
    RegExp(r'in\s+([A-Za-z0-9\s\-_&()]+?)\s+in\s+folio', caseSensitive: false),
    RegExp(
      r'(?:SIP|purchase|investment|alloted|allotted|installment|units|redemption|switch)\s+(?:[\w\d,\.\-]+\s+){0,6}in\s+(?:scheme\s+)?([A-Za-z0-9\s\-_&()]+?)(?:\s+(?:has been|is|processed|allotted|credited|successfully|via|under|against)|,|\s+dated|$)',
      caseSensitive: false,
    ),
    RegExp(
      r'in\s+(?:scheme\s+)?([A-Za-z0-9\s\-_&()]+(?:Fund|Plan|Growth|Equity|ETF)[A-Za-z0-9\s\-_&()]*?)(?:\s+(?:has|subject|for|with|under|against)|$)',
      caseSensitive: false,
    ),
  ];

  for (final pattern in fundPatterns) {
    final match = pattern.firstMatch(content);
    final rawName = match?.group(1);
    if (rawName == null) continue;

    var name = rawName.trim().replaceFirst(RegExp(r'^(your|the)\s+', caseSensitive: false), '');
    const stopWords = [
      ' has ', ' is ', ' processed', ' allotted', ' subject', ' for ', ' successfully', ' with ',
      ' under ', ' against ',
    ];
    for (final stop in stopWords) {
      final idx = name.toLowerCase().indexOf(stop);
      if (idx > 0) name = name.substring(0, idx);
    }

    if (name.length > 5 && name.length < 80) {
      if (RegExp(r'^Folio', caseSensitive: false).hasMatch(name) ||
          RegExp(r'^NAV', caseSensitive: false).hasMatch(name)) {
        continue; // extraction error — try the next pattern
      }
      details.investmentName = name.trim();
      break;
    }
  }

  // Sender-keyword lookup first: it always yields the same normalised
  // label ("Axis MF") for a given AMC, which is what grouping-by-AMC
  // depends on. The free-text signature regex below is a much looser
  // match — it captures whatever text happens to precede "...MF"/"...
  // Mutual Fund" at the tail of the SMS, which varies message-to-message
  // even for the same sender (different whitespace, prefix wording,
  // trailing punctuation). Running it first, as before, meant it almost
  // always won and produced a slightly different `amc` string per SMS —
  // so investments never actually grouped, since each message landed in
  // its own singleton bucket. It's now only a fallback for AMCs not in
  // the keyword list, and only if NPS detection above didn't already set
  // [amc].
  if (details.amc != null) {
    // NPS already assigned above — leave it as-is.
  } else if (RegExp(r'Axis', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Axis MF';
  } else if (RegExp(r'SBI', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'SBI MF';
  } else if (RegExp(r'IPRUMF', caseSensitive: false).hasMatch(sender) ||
      RegExp(r'ICICI', caseSensitive: false).hasMatch(sender)) {
    // Real-world DLT sender IDs for ICICI Prudential MF are typically
    // "IPRUMF" (no "ICICI" substring at all), not the bank's own "ICICI*"
    // codes — check both so this AMC groups correctly either way.
    details.amc = 'ICICI Pru MF';
  } else if (RegExp(r'HDFC', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'HDFC MF';
  } else if (RegExp(r'Mirae', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Mirae Asset MF';
  } else if (RegExp(r'Kotak', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Kotak MF';
  } else if (RegExp(r'Nippon', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Nippon India MF';
  } else if (RegExp(r'Dsp', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'DSP MF';
  } else if (RegExp(r'Uti', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'UTI MF';
  } else if (RegExp(r'QNTAMC|Quant', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Quant MF';
  } else if (RegExp(r'BOIAMC', caseSensitive: false).hasMatch(sender)) {
    details.amc = 'Bank of India MF';
  } else if (RegExp(r'ABCAMC', caseSensitive: false).hasMatch(sender)) {
    // Sender ID "ABCAMC" is Aditya Birla Sun Life MF's DLT header — the
    // message body signs off inconsistently ("-ABSLMF." on some, "Aditya
    // Birla Sun Life Mutual Fund." on others), which would otherwise
    // fragment this AMC's investments into two separate groups.
    details.amc = 'Aditya Birla Sun Life MF';
  } else {
    final amcMatch = RegExp(
      r'(?:Regards|From|Thanks)?[\s,\.\-]*([A-Za-z\s]+MF|[A-Za-z\s]+Mutual\s+Fund)[^a-z]*$',
      caseSensitive: false,
    ).firstMatch(content);
    final rawAmc = amcMatch?.group(1);
    if (rawAmc != null) {
      // Collapse repeated whitespace so trivial formatting differences
      // between messages from the same unrecognised AMC still land in
      // the same group.
      details.amc = rawAmc.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
  }

  // Fallback: derive units from amount ÷ NAV if units weren't stated directly.
  if (details.units == null && details.nav != null && details.nav! > 0) {
    final amountMatch =
        RegExp(r'(?:Rs\.?|INR)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(content);
    final amountRaw = amountMatch?.group(1);
    if (amountRaw != null) {
      final amount = double.tryParse(amountRaw.replaceAll(',', ''));
      if (amount != null && amount > 0) {
        details.units = double.parse((amount / details.nav!).toStringAsFixed(4));
      }
    }
  }

  return details;
}

// ---------------------------------------------------------------------------
// extractInvestmentValueStatement
// ---------------------------------------------------------------------------

class ExtractedInvestmentValueStatement {
  final double value;
  final DateTime? asOfDate;
  const ExtractedInvestmentValueStatement({required this.value, required this.asOfDate});
}

/// A periodic "here's what your holding is worth" statement — e.g. NPS/
/// Protean's "Investment value in Tier II (PRANXX8324) as on 31.03.25 is
/// Rs 1,04,683.33" — as opposed to a transaction. These never state
/// units/NAV (some NPS "Voluntary contribution" credit SMS don't either),
/// so [TransactionParserService.parseInvestmentValuation] uses this instead
/// of [extractInvestmentDetails]'s amount/NAV pipeline. Mirrors the keyword
/// pair categorization_service.dart already uses to route this message
/// shape to SmsCategory.updates ('investment value'/'total holding'/
/// 'current value' + 'as on'/'is rs') — this just extracts the amount/date
/// that categorization itself doesn't need. Returns null if the "is Rs X"
/// value can't be found, even if the message matched those keywords.
ExtractedInvestmentValueStatement? extractInvestmentValueStatement(String content) {
  final contentLower = content.toLowerCase();
  final hasValueKeyword = contentLower.contains('investment value') ||
      contentLower.contains('total holding') ||
      contentLower.contains('current value');
  if (!hasValueKeyword) return null;

  final valueMatch =
      RegExp(r'is\s+Rs\.?\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(content);
  final rawValue = valueMatch?.group(1);
  if (rawValue == null) return null;
  final value = double.tryParse(rawValue.replaceAll(',', ''));
  if (value == null) return null;

  final dateMatch = RegExp(r'as\s+on\s+([\d./\-]+)', caseSensitive: false).firstMatch(content);
  final rawDate = dateMatch?.group(1);
  final asOfDate = rawDate != null ? tryParseFlexibleDate(rawDate) : null;

  return ExtractedInvestmentValueStatement(value: value, asOfDate: asOfDate);
}

// ---------------------------------------------------------------------------
// extractFastagWalletId
// ---------------------------------------------------------------------------

String? extractFastagWalletId(String content) {
  final lower = content.toLowerCase();
  if (!lower.contains('fastag') && !lower.contains('toll')) return null;

  final patterns = [
    RegExp(
      r'(?:fastag\s*(?:wallet|account|id)?|wallet\s*id)[\s:.-]*(?:xx|x{2,4}|\*{2,4})(\d{4,12})\b',
      caseSensitive: false,
    ),
    RegExp(r'(?:fastag\s*id|wallet\s*id)[\s:.-]*([a-zA-Z0-9]{4,12})\b', caseSensitive: false),
    RegExp(r'(?:netc\s*fastag|fastag\s*account)[\s:.-]*(\d{10,16})\b', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final value = pattern.firstMatch(content)?.group(1);
    if (value == null) continue;
    if (RegExp(r'^\d{4}$').hasMatch(value)) return 'XX$value';
    return value.toUpperCase();
  }
  return null;
}

// ---------------------------------------------------------------------------
// extractVehicleNumber
// ---------------------------------------------------------------------------

const _vehiclePattern = r'([A-Z]{2}[-\s]?[A-Z0-9]{1,2}[-\s]?[A-Z]{0,3}[-\s]?[0-9]{4})\b';

String? extractVehicleNumber(String content) {
  final patterns = [
    RegExp('(?:veh|vehicle|vrn|reg\\s*no|for)[^\\w]*$_vehiclePattern', caseSensitive: false),
    RegExp('(?:fastag|toll|to).{0,40}\\b$_vehiclePattern', caseSensitive: false),
    RegExp('\\b$_vehiclePattern.{0,40}(?:fastag|toll)', caseSensitive: false),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(content)?.group(1);
    if (match != null) return match.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
  }
  return null;
}
