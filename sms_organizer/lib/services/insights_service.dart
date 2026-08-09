import '../models/transaction.dart';

/// How finely [InsightsSummary.trend] buckets transactions — chosen by the
/// caller to match how wide a date range it's summarizing (a single month
/// reads best bucketed by day; a whole year needs to be by month, or
/// there'd be hundreds of bars).
enum TrendGranularity { day, week, month }

class TrendPoint {
  final DateTime date; // bucket start; meaning depends on the granularity used to build it
  final double credit;
  final double debit;
  TrendPoint(this.date, this.credit, this.debit);
}

class InstrumentSummary {
  /// Matches [Transaction.instrumentGroupKey] for the transactions that fed
  /// this summary — lets drilldowns filter the full transaction list back
  /// down to just the ones behind this row. Stored directly (rather than
  /// re-derived from [types]/[issuer]/[ref]) so the two never drift apart —
  /// [Transaction.instrumentGroupKey] merges debit-card and bank-account
  /// entries that share an issuer + last-4, which a single [type] field
  /// can't represent on its own.
  final String key;
  final EntityType entityType;
  final String? ref; // e.g. "XX1234", or "Pluxee Card" for numberless cards
  final String? issuer;
  final String? walletType; // e.g. "Fuel Wallet", "HDFC FASTag"

  /// Every distinct [InstrumentType] seen among the transactions grouped
  /// under [key] — usually just one, but a merged debit-card+bank-account
  /// group carries both, which the segregated Cards & Accounts view uses
  /// to bucket it and to show a "Debit Card + Bank Account" badge.
  final Set<InstrumentType> types = {};

  double totalCredit = 0;
  double totalDebit = 0;
  int count = 0;

  /// Balance the most recent transaction (within the summarized range) that
  /// actually mentioned one reported — null if none of them did. Tracked
  /// alongside its date purely to know which transaction is "most recent"
  /// as they're folded in; the date itself isn't shown anywhere.
  double? lastBalance;
  DateTime? _lastBalanceDate;

  InstrumentSummary({
    required this.key,
    this.entityType = EntityType.unknown,
    this.ref,
    this.issuer,
    this.walletType,
  });

  void _considerBalance(double? balance, DateTime date) {
    if (balance == null) return;
    if (_lastBalanceDate == null || date.isAfter(_lastBalanceDate!)) {
      lastBalance = balance;
      _lastBalanceDate = date;
    }
  }

  /// The single instrument type driving this group, or the first one seen
  /// if it's a merged debit-card+bank-account group — used wherever a
  /// single icon/label is needed and the merge itself isn't relevant.
  InstrumentType get primaryType => types.isEmpty ? InstrumentType.unknown : types.first;

  bool get isCreditCard => types.contains(InstrumentType.creditCard);
  bool get isDebitCard => types.contains(InstrumentType.debitCard);
  bool get isBankAccount => types.contains(InstrumentType.bankAccount);
  bool get isLinkedAccount => types.length > 1;

  String get displayName {
    // A specific wallet name ("Fuel Wallet", "HDFC FASTag") is more useful
    // than a generic instrument label, so prefer it when we have one.
    if (walletType != null) return walletType!;

    final issuerPart = issuer ?? _instrumentLabel(primaryType);
    if (ref != null) return '$issuerPart ${_formatRef(ref!)}';
    return issuerPart;
  }

  /// e.g. "Debit Card", or "Debit Card + Bank Account" for a merged group.
  String get typeLabel {
    if (walletType != null) return 'Wallet';
    return types.map(_instrumentLabel).toSet().join(' + ');
  }

  /// "XX1234" -> "•• 1234"; anything else (e.g. "Pluxee Card") passes
  /// through as-is rather than getting a nonsensical "•• Pluxee Card".
  static String _formatRef(String ref) {
    if (RegExp(r'^XX\d+$').hasMatch(ref)) return '•• ${ref.substring(2)}';
    return '- $ref';
  }

  static String _instrumentLabel(InstrumentType t) {
    switch (t) {
      case InstrumentType.creditCard:
        return 'Credit Card';
      case InstrumentType.debitCard:
        return 'Debit Card';
      case InstrumentType.bankAccount:
        return 'Bank Account';
      case InstrumentType.upi:
        return 'UPI';
      case InstrumentType.unknown:
        return 'Other';
    }
  }
}

/// One row of [InsightsSummary.byMerchant] — see
/// [Transaction.merchantGroupKey] for how transactions are grouped into
/// these.
class MerchantSummary {
  final String key;

  /// Original casing of the first transaction seen for this merchant —
  /// [key] itself is lower-cased/normalised and not fit for display.
  final String displayName;

  double totalCredit = 0;
  double totalDebit = 0;
  int count = 0;

  MerchantSummary({required this.key, required this.displayName});
}

/// One row of [InsightsSummary.byCategory] — see [Transaction.spendCategory].
/// Unlike [InstrumentSummary]/[MerchantSummary], this is debit-only from the
/// ground up (not just in how it's charted): a spend-category breakdown
/// doesn't have a sensible "credit" side the way an account or merchant
/// does, so [totalDebit]/[count] only ever count debit transactions.
class SpendCategorySummary {
  /// Null for the "Uncategorised" bucket — every debit transaction the user
  /// hasn't tagged yet lands here, so the breakdown always accounts for the
  /// full spend total even before anyone's tagged anything.
  final SpendCategory? category;

  double totalDebit = 0;
  int count = 0;

  SpendCategorySummary({this.category});

  /// Stable string key for [BreakdownDonut]/drilldown filtering — mirrors
  /// [InstrumentSummary.key]/[MerchantSummary.key].
  String get key => category?.name ?? '_uncategorised';

  String get displayName => category?.label ?? 'Uncategorised';
}

class InsightsSummary {
  final double totalCredit;
  final double totalDebit;
  final int transactionCount;
  final List<InstrumentSummary> byInstrument;
  final List<MerchantSummary> byMerchant;
  final List<SpendCategorySummary> byCategory;
  final List<TrendPoint> trend;
  final TrendGranularity trendGranularity;
  final double totalInvested;
  final double totalRedeemed;
  final int investmentEventCount;

  InsightsSummary({
    required this.totalCredit,
    required this.totalDebit,
    required this.transactionCount,
    required this.byInstrument,
    required this.byMerchant,
    required this.byCategory,
    required this.trend,
    required this.trendGranularity,
    required this.totalInvested,
    required this.totalRedeemed,
    required this.investmentEventCount,
  });

  double get netFlow => totalCredit - totalDebit;
}

class InsightsService {
  InsightsSummary build({
    required List<Transaction> transactions,
    required List<InvestmentEvent> investments,
    DateTime? from,
    DateTime? to,
    TrendGranularity granularity = TrendGranularity.month,
  }) {
    final filtered = transactions.where((t) {
      if (from != null && t.date.isBefore(from)) return false;
      if (to != null && t.date.isAfter(to)) return false;
      return true;
    }).toList();

    double totalCredit = 0;
    double totalDebit = 0;
    final Map<String, TrendPoint> trendMap = {};

    for (final t in filtered) {
      if (t.direction == TxnDirection.credit) {
        totalCredit += t.amount;
      } else if (t.direction == TxnDirection.debit) {
        totalDebit += t.amount;
      }

      final bucketStart = trendBucketStart(t.date, granularity);
      final existing = trendMap[bucketStart.toIso8601String()];
      final newCredit = (existing?.credit ?? 0) + (t.direction == TxnDirection.credit ? t.amount : 0);
      final newDebit = (existing?.debit ?? 0) + (t.direction == TxnDirection.debit ? t.amount : 0);
      trendMap[bucketStart.toIso8601String()] = TrendPoint(bucketStart, newCredit, newDebit);
    }

    final trendList = _zeroFillTrend(trendMap.values.toList(), from, to, granularity);
    final instrumentList = groupByInstrument(filtered);
    final merchantList = groupByMerchant(filtered);
    final categoryList = groupBySpendCategory(filtered);

    double invested = 0;
    double redeemed = 0;
    int investmentEvents = 0;
    for (final inv in investments) {
      if (from != null && inv.date.isBefore(from)) continue;
      if (to != null && inv.date.isAfter(to)) continue;
      investmentEvents += 1;
      if (inv.kind == InvestmentKind.mutualFundRedemption) {
        redeemed += inv.amount;
      } else {
        invested += inv.amount;
      }
    }

    return InsightsSummary(
      totalCredit: totalCredit,
      totalDebit: totalDebit,
      transactionCount: filtered.length,
      byInstrument: instrumentList,
      byMerchant: merchantList,
      byCategory: categoryList,
      trend: trendList,
      trendGranularity: granularity,
      totalInvested: invested,
      totalRedeemed: redeemed,
      investmentEventCount: investmentEvents,
    );
  }

}

/// Groups [transactions] by [Transaction.instrumentGroupKey] into
/// per-instrument totals — a top-level function (not a method on
/// [InsightsService]) so it doubles as the re-derivation logic a drilldown
/// screen can call directly on a live subset of transactions (matched by
/// id) rather than carrying a static summary snapshot computed once at
/// navigation time. See InstrumentListScreen.
///
/// Only credit/debit transactions count toward [InstrumentSummary.count] —
/// a reversed or unknown-direction transaction still contributes to
/// [InstrumentSummary.types] (so its instrument still shows up at all) but
/// is excluded from the count, keeping "N transactions" in lockstep with
/// what totalCredit/totalDebit actually add up to instead of over-counting
/// against them.
List<InstrumentSummary> groupByInstrument(List<Transaction> transactions) {
  final map = <String, InstrumentSummary>{};
  for (final t in transactions) {
    final summary = map.putIfAbsent(
      t.instrumentGroupKey,
      () => InstrumentSummary(
        key: t.instrumentGroupKey,
        entityType: t.entityType,
        ref: t.instrumentRef,
        issuer: t.issuer,
        walletType: t.walletType,
      ),
    );
    summary.types.add(t.instrument);
    if (t.direction == TxnDirection.credit) {
      summary.totalCredit += t.amount;
      summary.count += 1;
    } else if (t.direction == TxnDirection.debit) {
      summary.totalDebit += t.amount;
      summary.count += 1;
    }
    summary._considerBalance(t.balanceAfter, t.date);
  }
  return map.values.toList()
    ..sort((a, b) => (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit));
}

/// Same idea as [groupByInstrument], grouped by [Transaction.merchantGroupKey]
/// — see there for why only credit/debit transactions count toward
/// [MerchantSummary.count].
List<MerchantSummary> groupByMerchant(List<Transaction> transactions) {
  final map = <String, MerchantSummary>{};
  for (final t in transactions) {
    final merchantKey = t.merchantGroupKey;
    if (merchantKey == null) continue;
    final merchant = map.putIfAbsent(
      merchantKey,
      () => MerchantSummary(key: merchantKey, displayName: t.merchant!.trim()),
    );
    if (t.direction == TxnDirection.credit) {
      merchant.totalCredit += t.amount;
      merchant.count += 1;
    } else if (t.direction == TxnDirection.debit) {
      merchant.totalDebit += t.amount;
      merchant.count += 1;
    }
  }
  return map.values.toList()
    ..sort((a, b) => (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit));
}

/// Groups [transactions] by [Transaction.spendCategory] — debit-only (see
/// [SpendCategorySummary]), including an "Uncategorised" bucket (`category:
/// null`) for every debit the user hasn't tagged yet, so the breakdown
/// always covers the full spend total rather than silently omitting
/// whatever isn't tagged.
List<SpendCategorySummary> groupBySpendCategory(List<Transaction> transactions) {
  final map = <String, SpendCategorySummary>{};
  for (final t in transactions) {
    if (t.direction != TxnDirection.debit) continue;
    final summary = map.putIfAbsent(
      t.spendCategory?.name ?? '_uncategorised',
      () => SpendCategorySummary(category: t.spendCategory),
    );
    summary.totalDebit += t.amount;
    summary.count += 1;
  }
  return map.values.toList()..sort((a, b) => b.totalDebit.compareTo(a.totalDebit));
}

/// Truncates [date] to the start of its bucket for [granularity] — a
/// calendar day, the Monday of its week, or the 1st of its month. Shared
/// (not just used by [InsightsService.build]) so other screens that bucket
/// their own data by the same granularity — e.g. the Investments "by AMC"
/// trend chart — stay in lockstep with how Insights buckets transactions.
DateTime trendBucketStart(DateTime date, TrendGranularity granularity) {
  switch (granularity) {
    case TrendGranularity.day:
      return DateTime(date.year, date.month, date.day);
    case TrendGranularity.week:
      final dayOnly = DateTime(date.year, date.month, date.day);
      return dayOnly.subtract(Duration(days: date.weekday - 1));
    case TrendGranularity.month:
      return DateTime(date.year, date.month);
  }
}

/// Every bucket-start date from [start] to [end] inclusive, stepping by
/// [granularity] — used to fill in zero-value buckets across a trend
/// chart's full time range rather than silently omitting the ones with no
/// data, which would compress the x-axis (bars stop being evenly spaced in
/// time, and a gap becomes invisible) and skew any "average per bucket"
/// figure derived from the point count (see TrendBarChart).
List<DateTime> bucketStartsBetween(DateTime start, DateTime end, TrendGranularity granularity) {
  final startBucket = trendBucketStart(start, granularity);
  final endBucket = trendBucketStart(end, granularity);
  final result = <DateTime>[];
  var current = startBucket;
  while (!current.isAfter(endBucket)) {
    result.add(current);
    current = switch (granularity) {
      TrendGranularity.day => current.add(const Duration(days: 1)),
      TrendGranularity.week => current.add(const Duration(days: 7)),
      TrendGranularity.month => DateTime(current.year, current.month + 1, 1),
    };
  }
  return result;
}

/// Fills gaps in [points] (only built for buckets that actually had a
/// transaction) with zero-value entries so a trend chart's bars are evenly
/// spaced in time — a month with no spend gets a visible zero bar instead of
/// silently vanishing from between its neighbours. Falls back to the
/// earliest/latest point's own date when [from]/[to] is null (the "all
/// time" range has no explicit bound to extend to), so allTime still stops
/// at the actual data rather than manufacturing empty buckets before/after it.
List<TrendPoint> _zeroFillTrend(
  List<TrendPoint> points,
  DateTime? from,
  DateTime? to,
  TrendGranularity granularity,
) {
  if (points.isEmpty) return [];
  final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
  final rangeStart = from ?? sorted.first.date;
  final rangeEnd = to ?? sorted.last.date;
  final byDate = {for (final p in sorted) p.date: p};
  return [
    for (final d in bucketStartsBetween(rangeStart, rangeEnd, granularity)) byDate[d] ?? TrendPoint(d, 0, 0),
  ];
}
