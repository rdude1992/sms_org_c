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

  InstrumentSummary({
    required this.key,
    this.entityType = EntityType.unknown,
    this.ref,
    this.issuer,
    this.walletType,
  });

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

class InsightsSummary {
  final double totalCredit;
  final double totalDebit;
  final int transactionCount;
  final List<InstrumentSummary> byInstrument;
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
    final Map<String, InstrumentSummary> instrumentMap = {};
    final Map<String, TrendPoint> trendMap = {};

    for (final t in filtered) {
      if (t.direction == TxnDirection.credit) {
        totalCredit += t.amount;
      } else if (t.direction == TxnDirection.debit) {
        totalDebit += t.amount;
      }

      final summary = instrumentMap.putIfAbsent(
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
      } else if (t.direction == TxnDirection.debit) {
        summary.totalDebit += t.amount;
      }
      summary.count += 1;

      final bucketStart = _bucketStart(t.date, granularity);
      final existing = trendMap[bucketStart.toIso8601String()];
      final newCredit = (existing?.credit ?? 0) + (t.direction == TxnDirection.credit ? t.amount : 0);
      final newDebit = (existing?.debit ?? 0) + (t.direction == TxnDirection.debit ? t.amount : 0);
      trendMap[bucketStart.toIso8601String()] = TrendPoint(bucketStart, newCredit, newDebit);
    }

    final trendList = trendMap.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final instrumentList = instrumentMap.values.toList()
      ..sort((a, b) => (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit));

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
      trend: trendList,
      trendGranularity: granularity,
      totalInvested: invested,
      totalRedeemed: redeemed,
      investmentEventCount: investmentEvents,
    );
  }

  /// Truncates [date] to the start of its bucket for [granularity] — a
  /// calendar day, the Monday of its week, or the 1st of its month.
  DateTime _bucketStart(DateTime date, TrendGranularity granularity) {
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
}
