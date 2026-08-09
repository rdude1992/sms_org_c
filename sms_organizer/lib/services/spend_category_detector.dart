import '../models/transaction.dart';

/// Best-effort automatic [SpendCategory] tagging so a user with a couple
/// thousand parsed transactions isn't stuck tagging every single one by
/// hand — a merchant/keyword match here is only ever a starting point
/// (never marked [Transaction.isOverridden]), so it's always one tap away
/// from being corrected via the transaction edit sheet, and never blocks a
/// real user choice from sticking.
///
/// Deliberately conservative: every rule below is a merchant name or a
/// category-specific keyword that's very unlikely to show up in an
/// unrelated SMS. Ambiguous purchases (a generic "paid to <name>" UPI
/// transfer with no other context) are left null ("Uncategorised") rather
/// than guessed — a wrong auto-tag is worse than none, since Insights'
/// spend-by-category totals would silently misattribute real money.
class SpendCategoryDetector {
  /// Bump whenever the rules below change, so SmsProvider's one-time
  /// backfill (see _backfillSpendCategories) re-runs over every
  /// still-uncategorised, non-overridden transaction rather than only ever
  /// applying to transactions parsed after the change.
  static const int version = 2;

  static SpendCategory? detect(Transaction t) {
    final haystack = [t.merchant, t.walletType, t.rawBody].whereType<String>().join(' ').toLowerCase();
    if (haystack.trim().isEmpty) return null;

    for (final rule in _rules) {
      if (rule.keywords.any(haystack.contains)) return rule.category;
    }

    // Direction-based fallbacks — about the *shape* of the transaction
    // (money coming in, no merchant/purpose named) rather than a guess at
    // what it was for, so these are safe even without a keyword hit.
    if (t.direction == TxnDirection.credit && t.merchant == null) {
      if (haystack.contains('salary') ||
          haystack.contains('interest credited') ||
          haystack.contains('interest paid') ||
          haystack.contains('dividend')) {
        return SpendCategory.income;
      }
    }
    if (t.direction == TxnDirection.debit &&
        t.merchant == null &&
        (haystack.contains('neft') || haystack.contains('imps') || haystack.contains('rtgs'))) {
      return SpendCategory.transfer;
    }

    return null;
  }
}

class _Rule {
  final List<String> keywords;
  final SpendCategory category;
  const _Rule(this.keywords, this.category);
}

const _rules = <_Rule>[
  _Rule([
    'swiggy', 'zomato', 'dominos', "domino's", 'pizza hut', 'mcdonald', 'kfc', 'burger king',
    'starbucks', 'faasos', 'box8', 'eatsure', 'behrouz', 'freshmenu', 'ovenstory',
  ], SpendCategory.foodDining),
  _Rule([
    'bigbasket', 'blinkit', 'zepto', 'grofers', 'jiomart', 'dmart', 'nature\'s basket',
    'reliance fresh', 'spencer\'s retail', 'licious', 'instamart',
  ], SpendCategory.groceries),
  _Rule([
    'uber', 'ola cabs', 'olacabs', 'rapido', 'irctc', 'indian railways', 'redbus',
    'petrol pump', 'hpcl', 'iocl', 'bpcl', 'indian oil', 'fastag', 'ncmc', 'metro rail',
    'namma metro', 'delhi metro',
  ], SpendCategory.transport),
  _Rule([
    'amazon', 'flipkart', 'myntra', 'ajio', 'nykaa', 'meesho', 'snapdeal', 'tatacliq',
    'croma', 'reliance digital', 'decathlon', 'ikea', 'lenskart',
  ], SpendCategory.shopping),
  _Rule([
    'netflix', 'spotify', 'hotstar', 'prime video', 'bookmyshow', 'sonyliv', 'zee5',
    'gaana', 'wynk music', 'youtube premium', 'jiocinema',
  ], SpendCategory.entertainment),
  _Rule([
    'apollo pharmacy', 'apollo hospital', 'practo', '1mg', 'pharmeasy', 'medplus', 'netmeds',
    'fortis', 'max healthcare', 'diagnostic centre', 'diagnostics lab',
  ], SpendCategory.health),
  _Rule([
    'makemytrip', 'goibibo', 'indigo airlines', 'spicejet', 'air india', 'vistara', 'oyo rooms',
    'airbnb', 'yatra.com', 'cleartrip', 'ixigo', 'agoda',
  ], SpendCategory.travel),
  _Rule([
    'house rent', 'rent payment', 'landlord', 'society maintenance', 'maintenance charges',
  ], SpendCategory.housing),
  _Rule([
    'school fee', 'college fee', 'tuition fee', 'udemy', 'coursera', 'byju', 'unacademy', 'vedantu',
  ], SpendCategory.education),
  // Bank-side debit alerts for money moving into an investment — SIP/NAV/
  // folio-worded SMS get parsed as a dedicated InvestmentEvent well before
  // this ever runs (see TransactionParserService.parseInvestment), so this
  // rule only ever fires on the transactions that fall through that: a
  // broker/PPF/NPS top-up whose SMS is phrased like any other transfer.
  _Rule([
    'zerodha', 'groww', 'upstox', 'angel one', 'kite by zerodha', 'icici direct',
    'hdfc securities', 'motilal oswal', 'sharekhan', '5paisa', 'paytm money',
    'ppf', 'sukanya samriddhi', 'nps contribution', 'recurring deposit',
  ], SpendCategory.investment),
  _Rule([
    'electricity bill', 'water bill', 'gas bill', 'dth recharge', 'broadband bill',
    'mobile recharge', 'postpaid bill', 'prepaid recharge', 'airtel', 'jio recharge',
    'vodafone idea', 'bsnl', 'tata power', 'adani electricity', 'bescom', 'mahadiscom', 'tangedco',
  ], SpendCategory.billsUtilities),
];
