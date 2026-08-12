import '../models/transaction.dart';
import 'insights_service.dart' show TrendGranularity, bucketStartsBetween;

/// A holding's state immediately after processing one of its events, in
/// chronological order — the basis for "as of" reconstruction (no live NAV
/// feed exists, so every value/units/NAV figure is necessarily a snapshot
/// of what the last relevant SMS said, not a real-time one).
class HoldingSnapshot {
  final DateTime date;
  final double unitsHeld;

  /// Last NAV known as of this point — carried forward from the most
  /// recent event that stated one, since not every SIP/purchase SMS
  /// repeats it.
  final double? nav;

  /// Cumulative invested − redeemed as of this point (the running
  /// principal still "in" the holding, as opposed to [unitsHeld] × [nav]
  /// which is the *current* estimated worth of that principal).
  final double netInvested;

  const HoldingSnapshot({
    required this.date,
    required this.unitsHeld,
    required this.nav,
    required this.netInvested,
  });
}

/// One distinct fund holding: same AMC + fund/scheme + folio/account,
/// netted across every SIP/purchase/redemption event referencing it (see
/// [InvestmentEvent.holdingGroupKey]) — the unit NAV/units-held tracking
/// actually applies to, unlike the coarser AMC-level grouping the "By AMC"
/// tab otherwise uses.
class FundHolding {
  final String key;
  final String amc;
  final String? fundOrScheme;
  final String? folioOrAccount;
  final List<InvestmentEvent> events;
  final List<HoldingSnapshot> timeline;

  const FundHolding({
    required this.key,
    required this.amc,
    required this.fundOrScheme,
    required this.folioOrAccount,
    required this.events,
    required this.timeline,
  });

  String get displayName {
    final fund = fundOrScheme?.trim();
    if (fund != null && fund.isNotEmpty) return fund;
    return amc;
  }

  double get netInvested => timeline.isEmpty ? 0 : timeline.last.netInvested;
  double get unitsHeld => timeline.isEmpty ? 0 : timeline.last.unitsHeld;
  double? get latestNav => timeline.isEmpty ? null : timeline.last.nav;
  DateTime? get latestNavDate {
    for (var i = timeline.length - 1; i >= 0; i--) {
      if (timeline[i].nav != null) return timeline[i].date;
    }
    return null;
  }

  /// Units still held × the most recently seen NAV — "estimated" because
  /// it's only ever as fresh as the last SMS that mentioned a NAV, not a
  /// live market quote. Falls back to net invested (cost basis) when no
  /// NAV was ever captured for this holding (e.g. some NPS contribution
  /// SMS never state one), so it still contributes *something* to a value
  /// total instead of silently reading as zero.
  double get estimatedValue {
    if (unitsHeld <= 0) return 0;
    final nav = latestNav;
    return nav != null ? unitsHeld * nav : netInvested;
  }

  double get estimatedGain => estimatedValue - netInvested;
  double? get estimatedGainPct => netInvested <= 0 ? null : (estimatedGain / netInvested) * 100;

  /// The last timeline snapshot at or before [asOf], or a zeroed one if
  /// [asOf] predates this holding's first event.
  HoldingSnapshot snapshotAsOf(DateTime asOf) {
    HoldingSnapshot? last;
    for (final s in timeline) {
      if (s.date.isAfter(asOf)) break;
      last = s;
    }
    return last ?? HoldingSnapshot(date: asOf, unitsHeld: 0, nav: null, netInvested: 0);
  }

  double valueAsOf(DateTime asOf) {
    final s = snapshotAsOf(asOf);
    if (s.unitsHeld <= 0) return 0;
    return s.nav != null ? s.unitsHeld * s.nav! : s.netInvested;
  }
}

/// Groups [events] into [FundHolding]s and reconstructs each one's
/// unit/NAV/net-invested history event-by-event. `events` need not already
/// share a single AMC — callers scoped to one AMC (see AmcDetailScreen) and
/// callers spanning everything (the main Investments dashboard) both just
/// call this on whatever set they have.
List<FundHolding> computeFundHoldings(List<InvestmentEvent> events) {
  final byKey = <String, List<InvestmentEvent>>{};
  for (final e in events) {
    byKey.putIfAbsent(e.holdingGroupKey, () => []).add(e);
  }

  final holdings = <FundHolding>[];
  for (final entry in byKey.entries) {
    final sorted = [...entry.value]..sort((a, b) => a.date.compareTo(b.date));
    final timeline = <HoldingSnapshot>[];
    var units = 0.0;
    var net = 0.0;
    double? nav;
    for (final e in sorted) {
      if (e.kind.isRedemption) {
        net -= e.amount;
        if (e.units != null) units -= e.units!;
      } else {
        net += e.amount;
        if (e.units != null) units += e.units!;
      }
      if (e.nav != null) nav = e.nav;
      timeline.add(HoldingSnapshot(date: e.date, unitsHeld: units, nav: nav, netInvested: net));
    }
    final first = sorted.first;
    holdings.add(FundHolding(
      key: entry.key,
      amc: first.providerDisplayName,
      fundOrScheme: first.fundOrScheme,
      folioOrAccount: first.folioOrAccount,
      events: sorted,
      timeline: timeline,
    ));
  }
  return holdings..sort((a, b) => b.estimatedValue.compareTo(a.estimatedValue));
}

/// Bucketed (invested, estimated value) series across every holding in
/// [holdings] — each point is both figures *as of the end of that bucket*,
/// reusing the same bucket boundaries [InvestmentListScreen]'s existing
/// invested/redeemed trend chart already uses for the same [granularity],
/// so the two charts stay in lockstep.
List<({DateTime date, double invested, double value})> buildValueTrend(
  List<FundHolding> holdings,
  TrendGranularity granularity,
  DateTime? from,
  DateTime? to,
) {
  if (holdings.isEmpty) return [];
  final allDates = [for (final h in holdings) ...h.events.map((e) => e.date)]..sort();
  if (allDates.isEmpty) return [];

  final rangeStart = from ?? allDates.first;
  final rangeEnd = to ?? allDates.last;
  final buckets = bucketStartsBetween(rangeStart, rangeEnd, granularity);

  return [
    for (final bucketStart in buckets)
      (
        date: bucketStart,
        invested: holdings.fold<double>(
            0, (a, h) => a + h.snapshotAsOf(_bucketEnd(bucketStart, granularity, rangeEnd)).netInvested),
        value: holdings.fold<double>(
            0, (a, h) => a + h.valueAsOf(_bucketEnd(bucketStart, granularity, rangeEnd))),
      ),
  ];
}

/// The instant a bucket's figures are "as of" — just before the next
/// bucket starts, capped to [cap] (the range's own end, or "now" in
/// practice) so the final, still-in-progress bucket reads as of today
/// rather than as of some not-yet-reached future date.
DateTime _bucketEnd(DateTime bucketStart, TrendGranularity granularity, DateTime cap) {
  final next = switch (granularity) {
    TrendGranularity.day => bucketStart.add(const Duration(days: 1)),
    TrendGranularity.week => bucketStart.add(const Duration(days: 7)),
    TrendGranularity.month => DateTime(bucketStart.year, bucketStart.month + 1, 1),
  };
  final end = next.subtract(const Duration(milliseconds: 1));
  return end.isAfter(cap) ? cap : end;
}

/// The NAV actually stated on each event that carried one — plotted as
/// literal SMS-detected points rather than bucketed/interpolated, since
/// NAV updates happen exactly when a purchase/redemption SMS says so and
/// synthesizing values in between would misrepresent what's actually known.
List<({DateTime date, double nav})> navHistory(FundHolding holding) => [
      for (final e in holding.events)
        if (e.nav != null) (date: e.date, nav: e.nav!),
    ];

/// Cumulative units held after each event — like [navHistory], plotted at
/// the real event dates rather than bucketed.
List<({DateTime date, double units})> unitsHistory(FundHolding holding) => [
      for (final s in holding.timeline) (date: s.date, units: s.unitsHeld),
    ];

/// A detected recurring monthly contribution — surfaced as "Monthly SIP
/// ₹X · live since <date>" even for holdings whose SMS never explicitly
/// tagged themselves as a SIP (TransactionParserService only sets
/// InvestmentKind.mutualFundSip when the SMS itself says "SIP"; plenty of
/// SIP debit SMS just read as a plain purchase).
class SipInfo {
  final double amount;
  final DateTime since;
  final int installments;
  const SipInfo({required this.amount, required this.since, required this.installments});
}

/// Heuristic: the purchase amount (rounded to the nearest rupee) that
/// recurs across at least 3 distinct calendar months is treated as the
/// SIP amount; ties go to whichever recurs most often. Returns null when
/// no amount clears that bar — a one-off lump-sum purchase, or too few
/// purchase events to tell a pattern from coincidence.
SipInfo? detectSip(FundHolding holding) {
  final purchases = holding.events.where((e) => !e.kind.isRedemption).toList();
  if (purchases.length < 3) return null;

  final byAmount = <int, List<InvestmentEvent>>{};
  for (final e in purchases) {
    byAmount.putIfAbsent(e.amount.round(), () => []).add(e);
  }

  List<InvestmentEvent>? best;
  for (final group in byAmount.values) {
    final distinctMonths = group.map((e) => e.date.year * 12 + e.date.month).toSet();
    if (distinctMonths.length < 3) continue;
    if (best == null || group.length > best.length) best = group;
  }
  if (best == null) return null;

  final sorted = [...best]..sort((a, b) => a.date.compareTo(b.date));
  return SipInfo(amount: sorted.first.amount, since: sorted.first.date, installments: sorted.length);
}
