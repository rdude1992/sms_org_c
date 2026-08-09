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

enum InsightsRange { allTime, thisMonth, last3Months, thisYear }

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
    }
  }

  /// The (from, to) window this range covers, as of [now]. `allTime` has no
  /// bound on either end.
  (DateTime?, DateTime?) boundsFrom(DateTime now) {
    switch (this) {
      case InsightsRange.allTime:
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
  /// ranges bucket coarser.
  TrendGranularity get trendGranularity {
    switch (this) {
      case InsightsRange.thisMonth:
        return TrendGranularity.day;
      case InsightsRange.last3Months:
        return TrendGranularity.week;
      case InsightsRange.thisYear:
      case InsightsRange.allTime:
        return TrendGranularity.month;
    }
  }

  /// How many calendar months back the "vs prev." comparison window should
  /// be shifted — null for `allTime`, which has no meaningful prior period.
  /// `thisYear` shifts a full 12 months rather than "however many months
  /// have elapsed so far this year", so it reads as a year-over-year
  /// comparison (same Jan 1–to-date window, one year earlier) rather than
  /// an odd partial-year lookback.
  int? get comparisonMonthsBack {
    switch (this) {
      case InsightsRange.allTime:
        return null;
      case InsightsRange.thisMonth:
        return 1;
      case InsightsRange.last3Months:
        return 3;
      case InsightsRange.thisYear:
        return 12;
    }
  }

  String get trendTitle {
    switch (trendGranularity) {
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

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final now = DateTime.now();
        final (from, to) = _range.boundsFrom(now);
        final summary =
            provider.insightsSummary(from: from, to: to, granularity: _range.trendGranularity);

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
        final monthsBack = _range.comparisonMonthsBack;
        if (from != null && monthsBack != null) {
          final prevFrom = _shiftMonths(from, monthsBack);
          final prevTo = _shiftMonths(to ?? now, monthsBack);
          previousSummary = provider.insightsSummary(from: prevFrom, to: prevTo);
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
                onSelected: (r) => setState(() => _range = r),
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
                                  subtitle: _range.label,
                                  transactions: filteredTransactions
                                      .where((t) => t.direction == direction)
                                      .toList(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(_range.trendTitle, style: Theme.of(context).textTheme.titleMedium),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('By card / account',
                                      style: Theme.of(context).textTheme.titleMedium),
                                  if (summary.byInstrument.isNotEmpty)
                                    TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => InstrumentListScreen(
                                            transactions: filteredTransactions,
                                            subtitle: _range.label,
                                          ),
                                        ),
                                      ),
                                      child: const Text('See all'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (summary.byInstrument.isNotEmpty) ...[
                                _InstrumentDonut(
                                  instruments: summary.byInstrument,
                                  filteredTransactions: filteredTransactions,
                                  rangeLabel: _range.label,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (summary.byInstrument.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No transactions in this range.',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                                          subtitle: _range.label,
                                          transactions: filteredTransactions
                                              .where((t) => t.instrumentGroupKey == s.key)
                                              .toList(),
                                        ),
                                      ),
                                    ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('By merchant', style: Theme.of(context).textTheme.titleMedium),
                                  if (summary.byMerchant.isNotEmpty)
                                    TextButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MerchantListScreen(
                                            transactions: filteredTransactions,
                                            subtitle: _range.label,
                                          ),
                                        ),
                                      ),
                                      child: const Text('See all'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (summary.byMerchant.isNotEmpty) ...[
                                _MerchantDonut(
                                  merchants: summary.byMerchant,
                                  filteredTransactions: filteredTransactions,
                                  rangeLabel: _range.label,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (summary.byMerchant.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No merchants detected in this range.',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                )
                              else
                                ...summary.byMerchant.take(6).map(
                                      (s) => _MerchantRow(
                                        summary: s,
                                        onTap: () => _openDrilldown(
                                          context,
                                          title: s.displayName,
                                          subtitle: _range.label,
                                          transactions: filteredTransactions
                                              .where((t) => t.merchantGroupKey == s.key)
                                              .toList(),
                                        ),
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
                                              subtitle: _range.label,
                                            ),
                                          ),
                                        ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Recent transactions',
                                      style: Theme.of(context).textTheme.titleMedium),
                                  TextButton(
                                    onPressed: () => _openDrilldown(
                                      context,
                                      title: 'All transactions',
                                      subtitle: _range.label,
                                      transactions: filteredTransactions,
                                    ),
                                    child: Text('${summary.transactionCount} total · See all'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ...filteredTransactions.take(15).map((t) => TransactionTile(transaction: t)),
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
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(title: title, subtitle: subtitle, transactions: transactions),
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
      subtitle: _range.label,
      transactions: transactions.where(matchesBucket).toList(),
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
      subtitle: Text('${summary.count} transactions'),
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
