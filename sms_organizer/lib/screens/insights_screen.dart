import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/ui/breakdown_donut.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/filter_chip_bar.dart';
import '../widgets/ui/trend_bar_chart.dart';
import 'instrument_list_screen.dart';
import 'investment_list_screen.dart';
import 'merchant_list_screen.dart';
import 'transaction_list_screen.dart';

/// `custom` covers a user-picked (via showDateRangePicker) arbitrary span —
/// unlike the other four, it has no fixed formula for its bounds/label/
/// trend granularity/previous-period comparison, so every method below
/// falls back to a placeholder for it and _InsightsScreenState computes the
/// real values itself from the picked DateTimeRange (see its
/// _effectiveBounds/_effectiveLabel/etc. getters). Every read of this enum's
/// extension members in this file goes through those getters instead of
/// calling straight through to here, specifically so `custom` is handled
/// correctly everywhere rather than just wherever someone remembered to
/// special-case it.
enum InsightsRange { allTime, thisMonth, last3Months, thisYear, custom }

extension on InsightsRange {
  String get label {
    switch (this) {
      case InsightsRange.allTime:
        return 'All time';
      case InsightsRange.thisMonth:
        return 'This month';
      case InsightsRange.last3Months:
        return 'Last 3 months';
      case InsightsRange.thisYear:
        return 'This year';
      case InsightsRange.custom:
        return 'Custom';
    }
  }

  /// The (from, to) window this range covers, as of [now]. `allTime` has no
  /// bound on either end. `custom`'s real bounds live in
  /// _InsightsScreenState's picked DateTimeRange, not here — this returns
  /// an all-time fallback purely so the method stays total.
  (DateTime?, DateTime?) boundsFrom(DateTime now) {
    switch (this) {
      case InsightsRange.allTime:
      case InsightsRange.custom:
        return (null, null);
      case InsightsRange.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case InsightsRange.last3Months:
        return (DateTime(now.year, now.month - 2, 1), now);
      case InsightsRange.thisYear:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  /// How finely the trend chart should bucket this range — day-by-day for
  /// a single month is readable, but the same granularity across a whole
  /// year (or all time) would be hundreds of unreadable bars, so wider
  /// ranges bucket coarser. `custom`'s real granularity is computed from
  /// the picked span's length (see _InsightsScreenState._effectiveTrendGranularity).
  TrendGranularity get trendGranularity {
    switch (this) {
      case InsightsRange.thisMonth:
        return TrendGranularity.day;
      case InsightsRange.last3Months:
        return TrendGranularity.week;
      case InsightsRange.thisYear:
      case InsightsRange.allTime:
      case InsightsRange.custom:
        return TrendGranularity.month;
    }
  }

  /// How many calendar months back the "vs prev." comparison window should
  /// be shifted — null for `allTime`, which has no meaningful prior period.
  /// `thisYear` shifts a full 12 months rather than "however many months
  /// have elapsed so far this year", so it reads as a year-over-year
  /// comparison (same Jan 1–to-date window, one year earlier) rather than
  /// an odd partial-year lookback. Also null for `custom` — an arbitrary
  /// picked span has no calendar-period equivalent to shift by, so its
  /// previous-period comparison falls back to a plain duration shift
  /// instead (see _InsightsScreenState's previousSummary computation).
  int? get comparisonMonthsBack {
    switch (this) {
      case InsightsRange.allTime:
      case InsightsRange.custom:
        return null;
      case InsightsRange.thisMonth:
        return 1;
      case InsightsRange.last3Months:
        return 3;
      case InsightsRange.thisYear:
        return 12;
    }
  }

  String trendTitleFor(TrendGranularity granularity) {
    switch (granularity) {
      case TrendGranularity.day:
        return 'Daily trend';
      case TrendGranularity.week:
        return 'Weekly trend';
      case TrendGranularity.month:
        return 'Monthly trend';
    }
  }
}

/// [date] shifted back by [months] calendar months, clamping the day of
/// month to the target month's actual length (e.g. Aug 31 minus one month
/// lands on Jul 31, not an overflowed Aug 1 via naive DateTime normalisation)
/// so a previous-period comparison never silently rolls into the wrong
/// month. Time-of-day is preserved so a same-time-of-day `to` bound (e.g.
/// "now") shifts cleanly too.
DateTime _shiftMonths(DateTime date, int months) {
  final targetYear = date.year;
  final targetMonth = date.month - months;
  final normalized = DateTime(targetYear, targetMonth, 1);
  final daysInTargetMonth = DateTime(normalized.year, normalized.month + 1, 0).day;
  final day = date.day > daysInTargetMonth ? daysInTargetMonth : date.day;
  return DateTime(
    normalized.year,
    normalized.month,
    day,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
  );
}

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  InsightsRange _range = InsightsRange.allTime;

  /// The user-picked span backing [InsightsRange.custom] — null until
  /// they've actually picked one via the date-range dialog (see
  /// [_selectRange]), even if `_range == InsightsRange.custom` was somehow
  /// reached without it (shouldn't happen, but every getter below treats a
  /// null [_customRange] as "fall back to all-time" rather than crashing).
  DateTimeRange? _customRange;

  /// Every other read of [_range]'s bounds/label/granularity in this file
  /// goes through these three getters/method instead of straight through to
  /// the enum extension, so `custom` is handled correctly everywhere rather
  /// than wherever someone remembered to special-case it — see
  /// [InsightsRange]'s doc comment.
  (DateTime?, DateTime?) _boundsFor(DateTime now) {
    final custom = _customRange;
    if (_range == InsightsRange.custom && custom != null) {
      final end = DateTime(custom.end.year, custom.end.month, custom.end.day, 23, 59, 59);
      return (custom.start, end);
    }
    return _range.boundsFrom(now);
  }

  String get _effectiveLabel {
    final custom = _customRange;
    if (_range == InsightsRange.custom && custom != null) {
      return '${Formatters.dayMonth(custom.start)} – ${Formatters.dayMonthYear(custom.end)}';
    }
    return _range.label;
  }

  /// Bucketed by the picked span's own length for `custom`, the same
  /// principle [InsightsRange.trendGranularity] applies to the fixed
  /// presets — day-by-day is readable for a couple of weeks, unreadable
  /// for a year.
  TrendGranularity get _effectiveTrendGranularity {
    final custom = _customRange;
    if (_range == InsightsRange.custom && custom != null) {
      final days = custom.end.difference(custom.start).inDays;
      if (days <= 31) return TrendGranularity.day;
      if (days <= 120) return TrendGranularity.week;
      return TrendGranularity.month;
    }
    return _range.trendGranularity;
  }

  /// Opens the date-range dialog for [InsightsRange.custom]; every other
  /// value just selects immediately. Cancelling the dialog leaves whatever
  /// range was already active untouched, rather than switching to an empty
  /// "custom, but nothing picked" state.
  Future<void> _selectRange(InsightsRange r) async {
    if (r != InsightsRange.custom) {
      setState(() => _range = r);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _range = InsightsRange.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final now = DateTime.now();
        final (from, to) = _boundsFor(now);
        final summary =
            provider.insightsSummary(from: from, to: to, granularity: _effectiveTrendGranularity);

        // Previous comparable period for the trend deltas — a true
        // calendar-month shift (see InsightsRange.comparisonMonthsBack), not
        // a raw duration subtraction. The old approach anchored the window
        // at `from` and walked back by however many days had elapsed since
        // it, which degenerates badly early in a period — e.g. on the 2nd of
        // the month it compared a single day against a single day from the
        // month before, and the compared dates weren't even the same
        // calendar days. Shifting both bounds back by whole months instead
        // gives "day 1–9 of this month" vs "day 1–9 of last month" and
        // "Jan 1–Aug 9 this year" vs "Jan 1–Aug 9 last year" — genuinely
        // comparable windows regardless of where in the period "now" falls.
        // Undefined (and hidden) for "All time" since there's no prior
        // window to compare against.
        InsightsSummary? previousSummary;
        if (from != null) {
          final monthsBack = _range.comparisonMonthsBack;
          if (monthsBack != null) {
            final prevFrom = _shiftMonths(from, monthsBack);
            final prevTo = _shiftMonths(to ?? now, monthsBack);
            previousSummary = provider.insightsSummary(from: prevFrom, to: prevTo);
          } else if (_range == InsightsRange.custom) {
            // A picked span has no calendar-period equivalent to shift by —
            // fall back to "the same-length window immediately before this
            // one". Unlike the presets this raw-duration approach used to
            // (badly) serve, a custom range has both ends fixed by the user
            // rather than one end trailing "now" mid-period, so there's no
            // partial-period ambiguity here to distort the comparison.
            final length = (to ?? now).difference(from);
            previousSummary = provider.insightsSummary(from: from.subtract(length), to: from);
          }
        }

        final filteredTransactions = provider.transactions.where((t) {
          if (from != null && t.date.isBefore(from)) return false;
          if (to != null && t.date.isAfter(to)) return false;
          return true;
        }).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        final filteredInvestments = provider.investments.where((i) {
          if (from != null && i.date.isBefore(from)) return false;
          if (to != null && i.date.isAfter(to)) return false;
          return true;
        }).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        // The true latest known balance per instrument, independent of
        // whatever range is selected — an account's balance is a snapshot,
        // not something that should disappear just because its most recent
        // balance-bearing SMS fell outside the chosen window.
        final lastBalanceByInstrument = <String, double>{
          for (final s in provider.insightsSummary().byInstrument)
            if (s.lastBalance != null) s.key: s.lastBalance!,
        };

        // Upcoming bills are forward-looking (due today or later), so they
        // deliberately ignore the selected range filter — every one of this
        // screen's ranges has `to` capped at "now", which would otherwise
        // hide every future due date under every single range option.
        final today = DateTime(now.year, now.month, now.day);
        final upcomingBills = provider.transactions
            .where((t) => t.billDueDate != null && !t.billDueDate!.isBefore(today))
            .toList()
          ..sort((a, b) => a.billDueDate!.compareTo(b.billDueDate!));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Insights'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: provider.refresh,
              ),
            ],
          ),
          body: Column(
            children: [
              _RangeFilterBar(
                selected: _range,
                onSelected: _selectRange,
              ),
              Expanded(
                child: provider.transactions.isEmpty
                    ? const EmptyState(
                        icon: Icons.insights_outlined,
                        title: 'No insights yet',
                        message: 'No transaction SMS detected yet. Once bank/card alerts arrive '
                            '(or after the first sync), spend and investment insights will show up here.',
                      )
                    : filteredTransactions.isEmpty
                        ? const EmptyState(
                            icon: Icons.filter_alt_off_outlined,
                            title: 'No transactions in this range',
                          )
                        : RefreshIndicator(
                            onRefresh: provider.refresh,
                            child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _TotalsRow(
                                summary: summary,
                                previous: previousSummary,
                                onTapDirection: (direction) => _openDrilldown(
                                  context,
                                  title: direction == TxnDirection.credit ? 'Credited' : 'Debited',
                                  subtitle: _effectiveLabel,
                                  transactions: filteredTransactions
                                      .where((t) => t.direction == direction)
                                      .toList(),
                                ),
                              ),
                              if (upcomingBills.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _UpcomingBillsCard(bills: upcomingBills),
                              ],
                              const SizedBox(height: 20),
                              // Recent transactions right after the summary, ahead of
                              // the detailed breakdowns below — "what happened lately"
                              // is usually what you're checking Insights for; the
                              // trend/by-card/by-merchant/by-category detail is there
                              // when you want it; not the first thing to scroll past.
                              _CollapsibleSection(
                                title: 'Recent transactions',
                                trailing: TextButton(
                                  onPressed: () => _openDrilldown(
                                    context,
                                    title: 'All transactions',
                                    subtitle: _effectiveLabel,
                                    transactions: filteredTransactions,
                                  ),
                                  child: Text('${summary.transactionCount} total · See all'),
                                ),
                                child: Column(
                                  children: [
                                    for (final t in filteredTransactions.take(15))
                                      TransactionTile(transaction: t),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(_range.trendTitleFor(_effectiveTrendGranularity),
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              _TrendChart(
                                summary: summary,
                                onTapBucket: (bucketStart) => _openTrendDrilldown(
                                  context,
                                  granularity: summary.trendGranularity,
                                  bucketStart: bucketStart,
                                  transactions: filteredTransactions,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _CollapsibleSection(
                                title: 'By card / account',
                                trailing: summary.byInstrument.isEmpty
                                    ? null
                                    : TextButton(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => InstrumentListScreen(
                                              transactions: filteredTransactions,
                                              subtitle: _effectiveLabel,
                                            ),
                                          ),
                                        ),
                                        child: const Text('See all'),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (summary.byInstrument.isNotEmpty) ...[
                                      _InstrumentDonut(
                                        instruments: summary.byInstrument,
                                        filteredTransactions: filteredTransactions,
                                        rangeLabel: _effectiveLabel,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (summary.byInstrument.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'No transactions in this range.',
                                          style:
                                              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    else
                                      ...summary.byInstrument.take(6).map(
                                            (s) => _InstrumentRow(
                                              summary: s,
                                              lastBalance: lastBalanceByInstrument[s.key],
                                              onTap: () => _openDrilldown(
                                                context,
                                                title: s.displayName,
                                                subtitle: _effectiveLabel,
                                                transactions: filteredTransactions
                                                    .where((t) => t.instrumentGroupKey == s.key)
                                                    .toList(),
                                                matches: (t) => t.instrumentGroupKey == s.key,
                                              ),
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _CollapsibleSection(
                                title: 'By merchant',
                                trailing: summary.byMerchant.isEmpty
                                    ? null
                                    : TextButton(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => MerchantListScreen(
                                              transactions: filteredTransactions,
                                              subtitle: _effectiveLabel,
                                            ),
                                          ),
                                        ),
                                        child: const Text('See all'),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (summary.byMerchant.isNotEmpty) ...[
                                      _MerchantDonut(
                                        merchants: summary.byMerchant,
                                        filteredTransactions: filteredTransactions,
                                        rangeLabel: _effectiveLabel,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (summary.byMerchant.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'No merchants detected in this range.',
                                          style:
                                              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    else
                                      ...summary.byMerchant.take(6).map(
                                            (s) => _MerchantRow(
                                              summary: s,
                                              onTap: () => _openDrilldown(
                                                context,
                                                title: s.displayName,
                                                subtitle: _effectiveLabel,
                                                transactions: filteredTransactions
                                                    .where((t) => t.merchantGroupKey == s.key)
                                                    .toList(),
                                                matches: (t) => t.merchantGroupKey == s.key,
                                              ),
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _CollapsibleSection(
                                title: 'By spend category',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (summary.byCategory.isNotEmpty) ...[
                                      _SpendCategoryDonut(
                                        categories: summary.byCategory,
                                        filteredTransactions: filteredTransactions,
                                        rangeLabel: _effectiveLabel,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (summary.byCategory.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'No spend in this range.',
                                          style:
                                              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      )
                                    else
                                      // No 6-item cap/"See all" here unlike By card / By
                                      // merchant — there are at most 13 spend categories
                                      // total (see SpendCategory), so the full list is
                                      // always short enough to show inline.
                                      // Every row here — Uncategorised included — only ever
                                      // counts debits (see SpendCategorySummary), so the
                                      // drilldown filters the same way: tapping a row always
                                      // lands on exactly the transactions its own count
                                      // covers, instead of Uncategorised jumping to the
                                      // full, every-direction backlog in Settings.
                                      ...summary.byCategory.map(
                                        (c) => _SpendCategoryRow(
                                          summary: c,
                                          onTap: () => _openDrilldown(
                                            context,
                                            title: c.displayName,
                                            subtitle: _effectiveLabel,
                                            transactions: filteredTransactions
                                                .where((t) =>
                                                    t.spendCategory == c.category &&
                                                    t.direction == TxnDirection.debit)
                                                .toList(),
                                            matches: (t) =>
                                                t.spendCategory == c.category &&
                                                t.direction == TxnDirection.debit,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _InvestmentCard(
                                summary: summary,
                                onTap: filteredInvestments.isEmpty
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => InvestmentListScreen(
                                              investments: filteredInvestments,
                                              allInvestments: provider.investments,
                                              subtitle: _effectiveLabel,
                                            ),
                                          ),
                                        ),
                              ),
                            ],
                            ),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDrilldown(
    BuildContext context, {
    required String title,
    required List<Transaction> transactions,
    String? subtitle,
    bool Function(Transaction)? matches,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(
          title: title,
          subtitle: subtitle,
          transactions: transactions,
          matches: matches,
        ),
      ),
    );
  }

  /// Same as [_openDrilldown], but for a tapped trend-chart bar — the
  /// matching window and title both depend on [granularity], since
  /// [bucketStart] means a different span (a day, a week, a month)
  /// depending on it.
  void _openTrendDrilldown(
    BuildContext context, {
    required TrendGranularity granularity,
    required DateTime bucketStart,
    required List<Transaction> transactions,
  }) {
    late final String title;
    late final bool Function(Transaction) matchesBucket;
    switch (granularity) {
      case TrendGranularity.day:
        title = Formatters.dayMonthYear(bucketStart);
        matchesBucket = (t) => Formatters.isSameDay(t.date, bucketStart);
        break;
      case TrendGranularity.week:
        final weekEnd = DateTime(bucketStart.year, bucketStart.month, bucketStart.day + 6, 23, 59, 59);
        title = 'Week of ${Formatters.dayMonth(bucketStart)}';
        matchesBucket = (t) => !t.date.isBefore(bucketStart) && !t.date.isAfter(weekEnd);
        break;
      case TrendGranularity.month:
        title = Formatters.monthYear(bucketStart);
        matchesBucket = (t) => t.date.year == bucketStart.year && t.date.month == bucketStart.month;
        break;
    }
    _openDrilldown(
      context,
      title: title,
      subtitle: _effectiveLabel,
      transactions: transactions.where(matchesBucket).toList(),
    );
  }
}

/// A titled section that can be collapsed to just its header — the page
/// grew long enough (Recent transactions, By card/account, By merchant, By
/// spend category, each with its own donut/list) that seeing the whole
/// thing meant a lot of scrolling even when you only care about one or two
/// of them. Expanded by default (so nothing looks hidden on first load);
/// [trailing] — usually a "See all" button — stays outside the
/// collapse/expand tap target and is always visible regardless of state.
/// State is local per section rather than lifted to [_InsightsScreenState]:
/// there's no cross-section behaviour that needs coordinating, and these
/// sections keep a stable position in a plain (non-builder) ListView, so
/// Flutter preserves each one's collapsed/expanded state across rebuilds
/// (range changes, provider refreshes) on its own.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _CollapsibleSection({required this.title, this.trailing, required this.child});

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(padding: const EdgeInsets.only(top: 4), child: widget.child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _RangeFilterBar extends StatelessWidget {
  final InsightsRange selected;
  final ValueChanged<InsightsRange> onSelected;
  const _RangeFilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return FilterChipBar<InsightsRange>(
      values: InsightsRange.values,
      selected: selected,
      labelBuilder: (r) => r.label,
      onSelected: onSelected,
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final InsightsSummary summary;
  final InsightsSummary? previous;
  final ValueChanged<TxnDirection> onTapDirection;

  const _TotalsRow({required this.summary, required this.previous, required this.onTapDirection});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TotalCard(
            label: 'Credited',
            value: summary.totalCredit,
            previousValue: previous?.totalCredit,
            color: const Color(0xFF10B981),
            icon: Icons.arrow_downward,
            // For money in, going up is good.
            increaseIsGood: true,
            onTap: () => onTapDirection(TxnDirection.credit),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TotalCard(
            label: 'Debited',
            value: summary.totalDebit,
            previousValue: previous?.totalDebit,
            color: const Color(0xFFEF4444),
            icon: Icons.arrow_upward,
            // For spend, going up is bad.
            increaseIsGood: false,
            onTap: () => onTapDirection(TxnDirection.debit),
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final double value;
  final double? previousValue;
  final Color color;
  final IconData icon;
  final bool increaseIsGood;
  final VoidCallback onTap;

  const _TotalCard({
    required this.label,
    required this.value,
    required this.previousValue,
    required this.color,
    required this.icon,
    required this.increaseIsGood,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                Formatters.currency(value),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
              if (previousValue != null) ...[
                const SizedBox(height: 6),
                _TrendBadge(current: value, previous: previousValue!, increaseIsGood: increaseIsGood),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double current;
  final double previous;
  final bool increaseIsGood;

  const _TrendBadge({required this.current, required this.previous, required this.increaseIsGood});

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    if (previous == 0 && current == 0) {
      return Text('No change', style: TextStyle(fontSize: 11, color: mutedColor));
    }
    final delta = current - previous;
    final pct = previous == 0 ? 100.0 : (delta / previous * 100).abs();
    final isUp = delta > 0;
    final isFlat = delta == 0;
    final favourable = isFlat ? null : (isUp == increaseIsGood);
    final color = isFlat
        ? mutedColor
        : (favourable! ? const Color(0xFF10B981) : const Color(0xFFEF4444));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFlat ? Icons.remove : (isUp ? Icons.arrow_upward : Icons.arrow_downward),
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '${pct.toStringAsFixed(0)}% vs prev.',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Stacked bar chart of credit/debit per [InsightsSummary.trend] bucket —
/// each bar's height is the bucket's total activity, split into a credit
/// segment and a debit segment stacked on top of it. Bucketing (day / week
/// / month) comes from [InsightsSummary.trendGranularity], set by the
/// selected [InsightsRange] — one bar per day for "This month" instead of
/// the single point a whole-range monthly bucket used to collapse into.
class _TrendChart extends StatelessWidget {
  final InsightsSummary summary;
  final ValueChanged<DateTime> onTapBucket;
  const _TrendChart({required this.summary, required this.onTapBucket});

  static const _creditColor = Color(0xFF10B981);
  static const _debitColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return TrendBarChart(
      dates: [for (final p in summary.trend) p.date],
      primaryValues: [for (final p in summary.trend) p.credit],
      secondaryValues: [for (final p in summary.trend) p.debit],
      granularity: summary.trendGranularity,
      primaryLabel: 'Credited',
      secondaryLabel: 'Debited',
      primaryColor: _creditColor,
      secondaryColor: _debitColor,
      onTapBucket: onTapBucket,
    );
  }
}

/// Surfaces [Transaction.billDueDate] — due today or later, soonest first.
/// Deliberately ignores the selected range filter (see where [bills] is
/// built in InsightsScreen.build) since a future due date would otherwise
/// never fall inside any range whose `to` bound is capped at "now".
///
/// Scope note: this only catches a due date mentioned *alongside* an
/// already-completed transaction in the same SMS (TransactionParserService
/// only runs on messages already confirmed transactional) — a standalone
/// "your bill is due" reminder with no completed-transaction language of
/// its own categorises as Updates and never reaches this list at all.
class _UpcomingBillsCard extends StatelessWidget {
  final List<Transaction> bills;
  const _UpcomingBillsCard({required this.bills});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Upcoming bills', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            for (final t in bills)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Due ${Formatters.dayMonthYear(t.billDueDate!)}',
                        style:
                            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
                      ),
                    ),
                    TransactionTile(transaction: t),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The top 6 instruments by *spend* (debit only) each get their own
/// [BreakdownDonut] slice, with anything past that folded into a single
/// "Other" slice so the chart doesn't fragment into slivers once someone
/// has a dozen linked cards.
///
/// Deliberately ranks and sizes slices by [InstrumentSummary.totalDebit]
/// alone, not totalCredit+totalDebit — a primarily-income account (e.g. a
/// salary account) would otherwise dominate a chart that reads as "where
/// does my money go", inflated by money arriving rather than being spent.
/// An instrument with no debit activity in range doesn't get a slice at
/// all; it still shows up in the row list below with both its credit and
/// debit totals, so nothing is hidden — just not folded into a spend pie
/// it isn't part of.
class _InstrumentDonut extends StatelessWidget {
  final List<InstrumentSummary> instruments;
  final List<Transaction> filteredTransactions;
  final String rangeLabel;

  const _InstrumentDonut({
    required this.instruments,
    required this.filteredTransactions,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bySpend = instruments.where((s) => s.totalDebit > 0).toList()
      ..sort((a, b) => b.totalDebit.compareTo(a.totalDebit));
    final top = bySpend.take(6).toList();
    final otherTotal = bySpend.skip(6).fold<double>(0, (a, s) => a + s.totalDebit);

    return BreakdownDonut(
      labels: [for (final s in top) s.displayName, if (otherTotal > 0) 'Other'],
      keys: [for (final s in top) s.key, if (otherTotal > 0) null],
      values: [for (final s in top) s.totalDebit, if (otherTotal > 0) otherTotal],
      centerLabel: 'spend',
      onTapKey: (key) {
        final match = instruments.firstWhere((s) => s.key == key);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionListScreen(
              title: match.displayName,
              subtitle: rangeLabel,
              transactions: filteredTransactions.where((t) => t.instrumentGroupKey == key).toList(),
              matches: (t) => t.instrumentGroupKey == key,
            ),
          ),
        );
      },
    );
  }
}

/// Same idea as [_InstrumentDonut] — ranked and sized by
/// [MerchantSummary.totalDebit] alone, not totalCredit+totalDebit, for the
/// same "this is a spend chart, not an activity chart" reason — grouped by
/// [Transaction.merchantGroupKey] instead of by instrument.
class _MerchantDonut extends StatelessWidget {
  final List<MerchantSummary> merchants;
  final List<Transaction> filteredTransactions;
  final String rangeLabel;

  const _MerchantDonut({
    required this.merchants,
    required this.filteredTransactions,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final bySpend = merchants.where((s) => s.totalDebit > 0).toList()
      ..sort((a, b) => b.totalDebit.compareTo(a.totalDebit));
    final top = bySpend.take(6).toList();
    final otherTotal = bySpend.skip(6).fold<double>(0, (a, s) => a + s.totalDebit);

    return BreakdownDonut(
      labels: [for (final s in top) s.displayName, if (otherTotal > 0) 'Other'],
      keys: [for (final s in top) s.key, if (otherTotal > 0) null],
      values: [for (final s in top) s.totalDebit, if (otherTotal > 0) otherTotal],
      centerLabel: 'spend',
      onTapKey: (key) {
        final match = merchants.firstWhere((s) => s.key == key);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionListScreen(
              title: match.displayName,
              subtitle: rangeLabel,
              transactions: filteredTransactions.where((t) => t.merchantGroupKey == key).toList(),
              matches: (t) => t.merchantGroupKey == key,
            ),
          ),
        );
      },
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  final InstrumentSummary summary;
  final double? lastBalance;
  final VoidCallback onTap;
  const _InstrumentRow({required this.summary, required this.lastBalance, required this.onTap});

  // UPI isn't its own instrument icon — it's a rail, and almost all UPI
  // activity now classifies as the bank account/card it actually moved
  // money through (see TransactionParserService._instrumentType). A bare
  // VPA mention with no account/card context at all falls through to the
  // generic icon below rather than getting a dedicated one.
  IconData get _icon {
    if (summary.walletType != null) return Icons.account_balance_wallet_outlined;
    if (summary.isCreditCard) return Icons.credit_card;
    if (summary.isDebitCard) return Icons.credit_card_outlined;
    if (summary.isBankAccount) return Icons.account_balance;
    return Icons.help_outline;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      minVerticalPadding: 10,
      leading: Icon(_icon),
      title: Text(summary.displayName),
      subtitle: Text(
        [
          if (summary.isLinkedAccount) summary.typeLabel,
          '${summary.count} transactions',
          if (lastBalance != null) 'Bal ${Formatters.currency(lastBalance!)}',
        ].join(' · '),
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('+${Formatters.currency(summary.totalCredit)}',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 12)),
          Text('-${Formatters.currency(summary.totalDebit)}',
              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _MerchantRow extends StatelessWidget {
  final MerchantSummary summary;
  final VoidCallback onTap;
  const _MerchantRow({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      minVerticalPadding: 10,
      leading: const Icon(Icons.storefront_outlined),
      title: Text(summary.displayName),
      subtitle: Text(
        '${summary.count} transactions',
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (summary.totalCredit > 0)
            Text('+${Formatters.currency(summary.totalCredit)}',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12)),
          if (summary.totalDebit > 0)
            Text('-${Formatters.currency(summary.totalDebit)}',
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Same idea as [_InstrumentDonut]/[_MerchantDonut] — top 6 + "Other" — but
/// [categories] is already debit-only from [groupBySpendCategory], so there's
/// no separate spend-only filter/re-sort needed here the way the other two
/// donuts have to do for themselves.
class _SpendCategoryDonut extends StatelessWidget {
  final List<SpendCategorySummary> categories;
  final List<Transaction> filteredTransactions;
  final String rangeLabel;

  const _SpendCategoryDonut({
    required this.categories,
    required this.filteredTransactions,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final top = categories.take(6).toList();
    final otherTotal = categories.skip(6).fold<double>(0, (a, c) => a + c.totalDebit);

    return BreakdownDonut(
      labels: [for (final c in top) c.displayName, if (otherTotal > 0) 'Other'],
      keys: [for (final c in top) c.key, if (otherTotal > 0) null],
      values: [for (final c in top) c.totalDebit, if (otherTotal > 0) otherTotal],
      centerLabel: 'spend',
      onTapKey: (key) {
        final match = categories.firstWhere((c) => c.key == key);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionListScreen(
              title: match.displayName,
              subtitle: rangeLabel,
              transactions: filteredTransactions
                  .where((t) => t.spendCategory == match.category && t.direction == TxnDirection.debit)
                  .toList(),
              matches: (t) => t.spendCategory == match.category && t.direction == TxnDirection.debit,
            ),
          ),
        );
      },
    );
  }
}

class _SpendCategoryRow extends StatelessWidget {
  final SpendCategorySummary summary;
  final VoidCallback onTap;
  const _SpendCategoryRow({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = summary.category?.color ?? Theme.of(context).colorScheme.outline;
    final icon = summary.category?.icon ?? Icons.label_off_outlined;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      minVerticalPadding: 10,
      leading: Icon(icon, color: color),
      title: Text(summary.displayName),
      subtitle: Text(
        '${summary.count} transaction${summary.count == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      ),
      trailing: Text(
        '-${Formatters.currency(summary.totalDebit)}',
        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}

class _InvestmentCard extends StatelessWidget {
  final InsightsSummary summary;
  final VoidCallback? onTap;
  const _InvestmentCard({required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Investments', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 18, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                        context, 'Invested', summary.totalInvested, Theme.of(context).colorScheme.primary),
                  ),
                  Expanded(
                    child: _miniStat(context, 'Redeemed', summary.totalRedeemed, const Color(0xFFF59E0B)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.investmentEventCount} SIP / mutual fund / trade SMS detected'
                '${onTap != null ? ' · tap to view' : ''}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Text(Formatters.currency(value),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
