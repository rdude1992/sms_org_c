import '../models/category.dart';
import '../models/sms_message.dart';
import '../utils/address_utils.dart';
import '../utils/sms_extractors.dart';

/// Ported from categorizeMessage(sender, content) in the source
/// smsParser.ts. This replaced an earlier, much simpler 4-bucket classifier
/// — the ordering and exclusion logic below (promo/future/request/bill
/// checks gating transaction detection, the priority-ordered checks up
/// top) all come directly from that source and matter for accuracy; don't
/// reorder blocks without checking the original intent first.
class CategorizationService {
  /// Bump this whenever [categorize]'s logic changes meaningfully, or
  /// whenever TransactionParserService's downstream parsing logic changes
  /// in a way that should reprocess already-cached transactions/investments
  /// (this is the only "wipe and redo everything" lever the app has).
  /// SmsProvider checks this against a value cached in the local database
  /// and automatically wipes + reprocesses everything once when it doesn't
  /// match — see SmsProvider._ensureCacheMatchesCurrentLogic. Without this,
  /// cached categories/transactions from before a logic change would
  /// silently keep being reused forever (incremental sync deliberately
  /// never re-evaluates cached entries on its own).
  static const int version = 12;

  // Short keywords that are also common substrings of unrelated words
  // ('win' in "window", 'bus' in "business", 'sip' in "gossip", 'nav' in
  // "navigate", 'ack' in "back"/"track", 'order' in "border", ...). These
  // match on word boundaries only, allowing a plural s/es. Every other
  // keyword stays a plain substring match, so stems like 'transfer' still
  // match "transferred".
  static final Map<String, RegExp> _boundaryKeywords = {
    for (final kw in const [
      'win', 'bus', 'sip', 'nav', 'train', 'order', 'free', 'deal', 'sale',
      'data', 'cab', 'ride', 'grab', 'limit', 'points', 'card', 'units',
    ])
      kw: RegExp('\\b$kw(?:s|es)?\\b'),
    'ack': RegExp(r'\back(?:nowledg\w*)?\b'),
  };

  /// Keyword test on already-lowercased text — see [_boundaryKeywords].
  static bool hasKeyword(String lower, String kw) {
    final boundary = _boundaryKeywords[kw];
    return boundary != null ? boundary.hasMatch(lower) : lower.contains(kw);
  }

  // "Never share your OTP/PIN with anyone" safety footers appear on most
  // Indian bank debit/credit alerts. They have to be removed before OTP
  // detection, or every such alert (whose A/c last-4 or 1800 helpline number
  // looks like a code) is classified as an OTP instead of a transaction.
  static final RegExp _otpWarning = RegExp(
    r"\b(?:never|do\s+not|don'?t|pls\s+do\s+not|please\s+do\s+not)\s+(?:share|disclose|tell|give)\b[^.!\n]*",
  );
  static final RegExp _digitCode = RegExp(r'\b\d{4,8}\b');
  // A code right next to an OTP word ("OTP is 482913", "482913 is your OTP").
  // Always an OTP, even when the message also names an amount.
  static final RegExp _explicitOtp = RegExp(
    r'\b(?:otp|one time password|verification code|passcode)\b[^.]{0,40}?\b\d{4,8}\b'
    r'|\b\d{4,8}\b[^.]{0,30}?\b(?:otp|one time password|verification code)\b',
  );
  static final RegExp _moneyMoved =
      RegExp(r'\b(?:debited|credited|spent|withdrawn|paid|sent|received|transferred)\b');
  static final RegExp _strongBankAlert = RegExp(r'\b(?:debited|credited)\b');
  static final RegExp _paymentReceived = RegExp(
    r'(?:payment|amount)[^.]{0,60}\b(?:received|credited)\b|received\s+towards',
  );
  static final RegExp _dltSuffix = RegExp(r'-([PSTG])$', caseSensitive: false);

  SmsCategory categorize(SmsMessage message) {
    final sender = message.address;
    final content = message.body;
    final contentLower = content.toLowerCase();
    final senderLower = sender.toLowerCase();
    final senderUpper = sender.toUpperCase();

    // OTP signals, computed up front because the personal-sender gate below
    // needs them too.
    final otpScan = contentLower.replaceAll(_otpWarning, ' ');
    const otpKeywords = [
      'otp', 'verification code', 'verify', 'code is', 'passcode', 'pin is',
      'one time password', 'auth code',
    ];
    final hasOtpKeyword = otpKeywords.any((kw) => otpScan.contains(kw));
    final hasDigitCode = _digitCode.hasMatch(otpScan);
    final hasAmount = extractAmount(content) != null;
    final isOtp = otpScan.contains('is your otp') ||
        _explicitOtp.hasMatch(otpScan) ||
        (hasOtpKeyword && hasDigitCode && !(hasAmount && _moneyMoved.hasMatch(otpScan)));

    // Personal senders: a plain 10-digit number with no DLT suffix is a
    // person (commercial senders use alphanumeric DLT headers). Keyword
    // scans must not run on their chats, or "are you free?", "send the
    // data", "on the bus" and "I paid 500 for dinner" end up promotional,
    // updates or transactional. Only unmistakable OTPs and bank alerts from
    // long codes are let through.
    if (isPhoneNumberAddress(sender) && !_dltSuffix.hasMatch(sender)) {
      if (isOtp) return SmsCategory.otp;
      if (hasAmount &&
          _strongBankAlert.hasMatch(contentLower) &&
          (contentLower.contains('a/c') ||
              contentLower.contains('account') ||
              contentLower.contains('upi'))) {
        return SmsCategory.transactional;
      }
      return SmsCategory.personal;
    }

    // A completed payment *received* ("Payment of Rs X received towards your
    // card... Total due Rs Y") mentions "due" too, but it is a transaction,
    // not a bill reminder.
    final isPaymentReceived = _paymentReceived.hasMatch(contentLower);

    // 0. Updates/Notifications (highest priority) — statements, nominee
    // notices, and "thank you" confirmations aren't personal, promotional,
    // or a transaction in themselves, even though they often come from the
    // same bank senders that also send real transaction alerts.
    if (contentLower.contains('view statement') ||
        contentLower.contains('account statement') ||
        contentLower.contains('a/c statement') ||
        contentLower.contains('download statement') ||
        contentLower.contains('statement of account') ||
        contentLower.contains('statement for folio') ||
        (contentLower.contains('stmt') &&
            (contentLower.contains('view') ||
                contentLower.contains('click') ||
                contentLower.contains('check'))) ||
        (contentLower.contains('redemption transaction') && contentLower.contains('processed')) ||
        (contentLower.contains('due') &&
            !isPaymentReceived &&
            (contentLower.contains('debit') ||
                contentLower.contains('payment') ||
                hasKeyword(contentLower, 'sip'))) ||
        contentLower.contains('nomination') ||
        contentLower.contains('nominee') ||
        contentLower.contains('thank you for choosing')) {
      return SmsCategory.updates;
    }

    // Investment/NPS balance alerts ("Investment value ... as on ...").
    if ((contentLower.contains('investment value') ||
            contentLower.contains('total holding') ||
            contentLower.contains('current value')) &&
        (contentLower.contains('as on') || contentLower.contains('is rs'))) {
      return SmsCategory.updates;
    }

    // Balance info without any transaction verb ("Available Balance: Rs X")
    // is a status ping, not a transaction.
    if ((contentLower.contains('available balance') ||
            contentLower.contains('account balance') ||
            contentLower.contains('clear balance') ||
            contentLower.contains('total balance')) &&
        !contentLower.contains('spent') &&
        !contentLower.contains('paid') &&
        !contentLower.contains('debited') &&
        !contentLower.contains('withdrawn') &&
        !contentLower.contains('sent to') &&
        !contentLower.contains('transferred to')) {
      return SmsCategory.updates;
    }

    // Stock-broker periodic snapshots ("ZERODHA BROKING LIMITED on <date>
    // reported your Fund bal Rs.X & Securities bal Y...") — a balance
    // reading, not a transaction; "broking" being in the transactional
    // sender allowlist below would otherwise let these through with a
    // meaningless direction/merchant since no money actually moved.
    if (contentLower.contains('reported your fund bal')) {
      return SmsCategory.updates;
    }

    // Sender-suffix hint: many Indian DLT-registered sender IDs end in a
    // single letter indicating the message class (-P promotional, -T
    // transactional, -S/-G service/government — both mapped to updates).
    final suffixMatch = _dltSuffix.firstMatch(sender);
    SmsCategory? suffixCategory;
    if (suffixMatch != null) {
      switch (suffixMatch.group(1)!.toUpperCase()) {
        case 'P':
          suffixCategory = SmsCategory.promotional;
        case 'S':
        case 'G':
          suffixCategory = SmsCategory.updates;
        case 'T':
          suffixCategory = SmsCategory.transactional;
      }
    }

    // 1. OTP detection (signals computed at the top, see [_otpWarning]).
    if (isOtp) return SmsCategory.otp;

    // 2. Transaction detection.
    const promoKeywords = [
      'offer', 'sale', 'discount', '% off', 'flat off', 'deal', 'free', 'win', 'prize',
      'cashback', 'coupon', 'limited time', 'hurry', 'shop now', 'buy now', 'grab',
      'exclusive', 'rewards', 'points', 'congrats', 'play now',
      'recharge', 'data', 'validity', 'use code',
      'create wealth', 'achieve your life goals', 'start a sip', 'opportunity',
      'nfo', 'new fund offer', 'is live', 'opens today', 'closes on', 'subscribe now',
      'markets have fallen', 'time to top up', 'click here to invest',
    ];
    final isPromotion = promoKeywords.any((kw) {
      if (kw == 'data' && contentLower.contains('data wallet')) return false;
      if ((kw == 'recharge' || kw == 'validity') &&
          (contentLower.contains('fastag') || senderUpper.contains('FASTAG'))) {
        return false;
      }
      // 'nfo' (New Fund Offer) as a bare substring also matches inside the
      // ordinary word "info"/"Info:" — a field label many routine bank
      // debit/credit alerts use (e.g. "Info: ACH D-..."). That falsely
      // flagged plain transaction SMS as promotional and blocked them from
      // ever being detected as transactions. Require a word boundary so
      // this only matches the standalone "NFO" abbreviation.
      if (kw == 'nfo') return RegExp(r'\bnfo\b', caseSensitive: false).hasMatch(content);
      return hasKeyword(contentLower, kw);
    });

    final isFutureTransaction =
        RegExp(r'will\s+be\s+(?:debited|credited)', caseSensitive: false).hasMatch(contentLower) ||
            RegExp(r'scheduled', caseSensitive: false).hasMatch(contentLower) ||
            RegExp(r'initiated', caseSensitive: false).hasMatch(contentLower);

    // A UPI/CRED-style collect request ("X has requested Rs.Y from you" /
    // "... has requested money from you on CRED") isn't money that has
    // moved yet — it's asking the user to approve a future debit. Some
    // gateways phrase the follow-up as "will be debited" (already caught
    // by isFutureTransaction below) but others (e.g. "To authorize debit
    // from your account please login...") don't, so without this check
    // those slip through as if they were completed transactions and
    // inflate spend totals for money that was never actually sent.
    final isPendingPaymentRequest =
        RegExp(r'has\s+requested\s+(?:Rs\.?|INR|₹|money)', caseSensitive: false).hasMatch(content) &&
            contentLower.contains('from you');

    final isRequestNotification = (contentLower.contains('request') &&
            (contentLower.contains('receipt') ||
                contentLower.contains('received') ||
                contentLower.contains('recd') ||
                contentLower.contains('cancel') ||
                contentLower.contains('redemption'))) ||
        (contentLower.contains('feedback') && contentLower.contains('important')) ||
        (hasKeyword(contentLower, 'ack') && contentLower.contains('receipt')) ||
        isPendingPaymentRequest;

    // hasAmount (computed at the top) uses the robust extractor: it handles
    // year false-positives, Pluxee's currency-symbol-less amounts, etc.

    const transactionKeywords = [
      'credited', 'debited', 'spent', 'paid', 'received', 'transfer',
      'balance', 'a/c', 'account', 'transaction', 'payment', 'upi', 'bank',
      'withdrawn', 'purchase', 'card', 'limit', 'pluxee', 'sodexo',
      'sip', 'folio', 'nav', 'units', 'equity', 'redemption', 'allotted',
    ];
    const bankSenders = [
      'bank', 'hdfc', 'icici', 'sbi', 'axis', 'kotak', 'paytm', 'phonepe',
      'gpay', 'upi', 'abcamc', 'miraei', 'mutual', 'fund', 'broking',
    ];

    if (suffixCategory == SmsCategory.transactional) return SmsCategory.transactional;

    // EPFO passbook SMS ("... Contribution of Rs.X for due month Feb-26
    // has been received.") name the contribution's *due period*, not an
    // unpaid bill — "due month Feb-26" would otherwise trip
    // isBillNotification below the same way an actual "payment due"
    // reminder does, and get routed to updates/dropped instead of
    // recorded as the PF credit it actually is. Requires both an
    // EPFO-specific signal and "contribution" together, so this stays
    // narrow enough not to also swallow an unrelated bill reminder that
    // happens to mention "provident fund" in passing.
    final isEpfoContribution = contentLower.contains('contribution') &&
        (contentLower.contains('epfo') ||
            contentLower.contains('provident fund') ||
            contentLower.contains('passbook balance'));

    if (hasAmount &&
        (transactionKeywords.any((kw) => hasKeyword(contentLower, kw)) ||
            bankSenders.any((bank) => senderLower.contains(bank)) ||
            RegExp(r'Pluxee', caseSensitive: false).hasMatch(content) ||
            RegExp(r'FASTag', caseSensitive: false).hasMatch(content) ||
            senderUpper.contains('FASTAG'))) {
      final isBillNotification = (contentLower.contains('due') || contentLower.contains('bill')) &&
          !contentLower.contains('paid') &&
          !contentLower.contains('debited') &&
          !isPaymentReceived &&
          !isEpfoContribution;

      final isMandateNotification = contentLower.contains('mandate registered') ||
          (contentLower.contains('mandate') && contentLower.contains('creation'));

      if (!isBillNotification &&
          !isMandateNotification &&
          !isFutureTransaction &&
          !isPromotion &&
          !isRequestNotification) {
        return SmsCategory.transactional;
      }
    }

    // Explicit investment checks, even without an exact amount match.
    if (!isFutureTransaction && !isRequestNotification && !isPromotion) {
      if (hasKeyword(contentLower, 'sip') &&
          (contentLower.contains('processed') ||
              contentLower.contains('due') ||
              contentLower.contains('installment'))) {
        return SmsCategory.transactional;
      }
      if (hasKeyword(contentLower, 'units') &&
          (contentLower.contains('nav') ||
              contentLower.contains('allotted') ||
              contentLower.contains('credited'))) {
        return SmsCategory.transactional;
      }
      if (contentLower.contains('folio')) return SmsCategory.transactional;
      if (contentLower.contains('mutual fund') || contentLower.contains(' mf ')) {
        return SmsCategory.transactional;
      }
    }

    // 3. Updates.
    if (suffixCategory == SmsCategory.updates) return SmsCategory.updates;

    const updateKeywords = [
      'delivered', 'out for delivery', 'dispatched', 'shipped', 'arriving', 'courier', 'package', 'order',
      'pnr', 'booking confirmed', 'ticket', 'flight', 'train', 'bus', 'cab', 'driver', 'ride',
      'bill generated', 'invoice', 'due date', 'statement', 'plan expire',
    ];
    if (updateKeywords.any((kw) => hasKeyword(contentLower, kw))) return SmsCategory.updates;

    // 4. Promotional.
    if (suffixCategory == SmsCategory.promotional) return SmsCategory.promotional;
    // Same 'nfo'-inside-"info" word-boundary fix as the isPromotion check
    // above — this is a separate keyword scan, not a reuse of that result,
    // so it needs the same guard rather than inheriting it.
    if (promoKeywords.any((kw) =>
        kw == 'nfo' ? RegExp(r'\bnfo\b', caseSensitive: false).hasMatch(content) : hasKeyword(contentLower, kw))) {
      return SmsCategory.promotional;
    }

    if (contentLower.contains('unsubscribe') ||
        contentLower.contains('opt-out') ||
        contentLower.contains('t&c')) {
      return SmsCategory.promotional;
    }

    // Phone-number senders were already routed by the personal gate at the
    // top; a DLT-suffixed one that reached this point falls through to updates.

    // Everything else (shortcodes, alphanumeric senders, etc.) defaults to updates.
    return SmsCategory.updates;
  }

  void categorizeAll(List<SmsMessage> messages) {
    for (final m in messages) {
      m.category = categorize(m);
    }
  }
}
