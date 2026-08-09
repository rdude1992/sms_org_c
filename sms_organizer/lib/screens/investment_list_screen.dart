import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/investment_tile.dart';
import '../widgets/ui/breakdown_donut.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/filter_chip_bar.dart';
import '../widgets/ui/total_stat.dart';
import '../widgets/ui/trend_bar_chart.dart';

/// How far back the "By AMC" tab's donut/trend chart look — independent of
/// whatever range brought the caller into this screen, so someone drilled
/// into a single provider's own investments (see [_ProviderRow]'s onTap)
/// can still slice that provider's history by time.
enum InvestmentRange { thisMonth, last3Months, last6Months, thisYear, allTime }

extension on InvestmentRange {
  String get label {
    switch (this) {
      case InvestmentRange.thisMonth:
        return 'This month';
      case InvestmentRange.last3Months:
        return 'Last 3 months';
      case InvestmentRange.last6Months:
        return 'Last 6 months';
      case InvestmentRange.thisYear:
        return 'This year';
      case InvestmentRange.allTime:
        return 'All time';
    }
  }

  /// The (from, to) window this range covers, as of [now]. `allTime` has no
  /// bound on either end.
  (DateTime?, DateTime?) boundsFrom(DateTime now) {
    switch (this) {
      case InvestmentRange.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case InvestmentRange.last3Months:
        return (DateTime(now.year, now.month - 2, 1), now);
      case InvestmentRange.last6Months:
        return (DateTime(now.year, now.month - 5, 1), now);
      case InvestmentRange.thisYear:
        return (DateTime(now.year, 1, 1), now);
      case InvestmentRange.allTime:
        return (null, null);
    }
  }

  /// How finely the trend chart should bucket this range — see
  /// InsightsRange.trendGranularity for the same idea applied to
  /// transactions.
  TrendGranularity get trendGranularity {
    switch (this) {
      case InvestmentRange.thisMonth:
        return TrendGranularity.day;
      case InvestmentRange.last3Months:
        return TrendGranularity.week;
      case InvestmentRange.last6Months:
      case InvestmentRange.thisYear:
      case InvestmentRange.allTime:
        return TrendGranularity.month;
    }
  }
}

/// Drilldown target for the Insights "Investments" card — mirrors
/// TransactionListScreen's All/split-direction tab pattern, split here into
/// By AMC/Invested/Redeemed/All since that's the distinction InvestmentKind
/// draws. "By AMC" — which groups events by AMC/broker (see
/// [InvestmentEvent.providerGroupKey]) and carries its own donut/trend
/// analytics — leads since it's the most useful breakdown; the flat "All"
/// list is closer to a raw data dump, so it's last.
class InvestmentListScreen extends StatelessWidget {
  final String? subtitle;
  final List<InvestmentEvent> investments;

  const InvestmentListScreen({super.key, required this.investments, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...investments]..sort((a, b) => b.date.compareTo(a.date));
    final invested = sorted.where((i) => !i.kind.isRedemption).toList();
    final redeemed = sorted.where((i) => i.kind.isRedemption).toList();
    final investedTotal = invested.fold<double>(0, (a, i) => a + i.amount);
    final redeemedTotal = redeemed.fold<double>(0, (a, i) => a + i.amount);
    final providers = _groupByProvider(sorted);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Investments'),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(subtitle == null ? 48 : 68),
            child: Column(
              children: [
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'By AMC (${providers.length})'),
                    Tab(text: 'Invested (${invested.length})'),
                    Tab(text: 'Redeemed (${redeemed.length})'),
                    Tab(text: 'All (${sorted.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? const EmptyState(icon: Icons.trending_up, title: 'No investment activity in this range')
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: scheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TotalStat(label: 'Invested', value: investedTotal, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TotalStat(
                              label: 'Redeemed', value: redeemedTotal, color: const Color(0xFFF59E0B)),
                        ),
                        // Builder gives us a context below DefaultTabController
                        // (the outer `context` here is this widget's own,
                        // which sits above it in the tree we're building) so
                        // DefaultTabController.of can actually find it.
                        Builder(
                          builder: (context) => InkWell(
                            borderRadius: BorderRadius.circular(6),
                            // Index 3 is the "All" tab — see the TabBar above.
                            onTap: () => DefaultTabController.of(context).animateTo(3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                '${sorted.length} events',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  decoration: TextDecoration.underline,
                                  decorationColor: scheme.onSurfaceVariant.withOpacity(0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _AmcListView(providers: providers, investments: sorted),
                        _InvestmentListView(investments: invested, emptyText: 'Nothing invested.'),
                        _InvestmentListView(investments: redeemed, emptyText: 'Nothing redeemed.'),
                        _InvestmentListView(investments: sorted, emptyText: 'No investment activity.'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InvestmentListView extends StatelessWidget {
  final List<InvestmentEvent> investments;
  final String emptyText;

  const _InvestmentListView({required this.investments, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (investments.isEmpty) {
      return EmptyState(icon: Icons.trending_up, title: emptyText);
    }
    return ListView.builder(
      itemCount: investments.length,
      itemBuilder: (context, index) => InvestmentTile(investment: investments[index]),
    );
  }
}

/// One row per AMC/broker (see [InvestmentEvent.providerGroupKey]) —
/// e.g. "Axis MF", "Zerodha", "NPS" — with invested/redeemed totals and
/// the events feeding it, for the "By AMC" tab.
class _ProviderSummary {
  final String key;
  final String name;
  double invested = 0;
  double redeemed = 0;
  final List<InvestmentEvent> events = [];

  _ProviderSummary({required this.key, required this.name});

  int get count => events.length;
  double get total => invested + redeemed;
}

List<_ProviderSummary> _groupByProvider(List<InvestmentEvent> investments) {
  final map = <String, _ProviderSummary>{};
  for (final i in investments) {
    final summary = map.putIfAbsent(
      i.providerGroupKey,
      () => _ProviderSummary(key: i.providerGroupKey, name: i.providerDisplayName),
    );
    if (i.kind.isRedemption) {
      summary.redeemed += i.amount;
    } else {
      summary.invested += i.amount;
    }
    summary.events.add(i);
  }
  return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

/// The "By AMC" tab: a self-contained analytics header — its own time
/// range filter driving a by-provider donut, an invested/redeemed trend
/// chart, and the provider rows below — so picking e.g. "This month" shows
/// only that month's events, counts and totals throughout the whole tab.
class _AmcListView extends StatefulWidget {
  final List<_ProviderSummary> providers;
  final List<InvestmentEvent> investments;

  const _AmcListView({required this.providers, required this.investments});

  @override
  State<_AmcListView> createState() => _AmcListViewState();
}

class _AmcListViewState extends State<_AmcListView> {
  InvestmentRange _range = InvestmentRange.allTime;

  @override
  Widget build(BuildContext context) {
    if (widget.providers.isEmpty) {
      return const EmptyState(icon: Icons.trending_up, title: 'No investment activity.');
    }

    final now = DateTime.now();
    final (from, to) = _range.boundsFrom(now);
    final filteredInvestments = widget.investments.where((i) {
      if (from != null && i.date.isBefore(from)) return false;
      if (to != null && i.date.isAfter(to)) return false;
      return true;
    }).toList();
    final filteredProviders = _groupByProvider(filteredInvestments);

    return ListView(
      children: [
        _AmcAnalytics(
          range: _range,
          onRangeSelected: (r) => setState(() => _range = r),
          investments: widget.investments,
        ),
        for (final p in filteredProviders) _ProviderRow(provider: p),
      ],
    );
  }
}

/// Range filter + by-provider donut + invested/redeemed trend chart for
/// the "By AMC" tab — filters [investments] by [range] internally rather
/// than taking an already-filtered list, so it can offer finer/coarser
/// windows than whatever range the caller filtered this whole screen to.
class _AmcAnalytics extends StatelessWidget {
  final InvestmentRange range;
  final ValueChanged<InvestmentRange> onRangeSelected;
  final List<InvestmentEvent> investments;

  const _AmcAnalytics({
    required this.range,
    required this.onRangeSelected,
    required this.investments,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final (from, to) = range.boundsFrom(now);
    final filtered = investments.where((i) {
      if (from != null && i.date.isBefore(from)) return false;
      if (to != null && i.date.isAfter(to)) return false;
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipBar<InvestmentRange>(
            values: InvestmentRange.values,
            selected: range,
            labelBuilder: (r) => r.label,
            onSelected: onRangeSelected,
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No investment activity in this range.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ..._buildCharts(context, filtered),
        ],
      ),
    );
  }

  List<Widget> _buildCharts(BuildContext context, List<InvestmentEvent> filtered) {
    final scheme = Theme.of(context).colorScheme;
    final providers = _groupByProvider(filtered);
    final topProviders = providers.take(6).toList();
    final otherProvidersTotal = providers.skip(6).fold<double>(0, (a, p) => a + p.total);

    void openProvider(String key) {
      final match = providers.firstWhere((p) => p.key == key);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentListScreen(investments: match.events, subtitle: match.name),
        ),
      );
    }

    // Bucketed invested/redeemed totals for the trend chart — same
    // granularity-by-range approach Insights uses for transactions (see
    // InsightsRange.trendGranularity), just applied to investment events.
    final buckets = <String, ({DateTime date, double invested, double redeemed})>{};
    for (final i in filtered) {
      final bucketStart = trendBucketStart(i.date, range.trendGranularity);
      final key = bucketStart.toIso8601String();
      final existing = buckets[key];
      final newInvested = (existing?.invested ?? 0) + (i.kind.isRedemption ? 0 : i.amount);
      final newRedeemed = (existing?.redeemed ?? 0) + (i.kind.isRedemption ? i.amount : 0);
      buckets[key] = (date: bucketStart, invested: newInvested, redeemed: newRedeemed);
    }
    final points = buckets.values.toList()..sort((a, b) => a.date.compareTo(b.date));

    void openBucket(DateTime bucketStart) {
      late final String title;
      late final bool Function(InvestmentEvent) matchesBucket;
      switch (range.trendGranularity) {
        case TrendGranularity.day:
          title = Formatters.dayMonthYear(bucketStart);
          matchesBucket = (i) => Formatters.isSameDay(i.date, bucketStart);
          break;
        case TrendGranularity.week:
          final weekEnd = DateTime(bucketStart.year, bucketStart.month, bucketStart.day + 6, 23, 59, 59);
          title = 'Week of ${Formatters.dayMonth(bucketStart)}';
          matchesBucket = (i) => !i.date.isBefore(bucketStart) && !i.date.isAfter(weekEnd);
          break;
        case TrendGranularity.month:
          title = Formatters.monthYear(bucketStart);
          matchesBucket = (i) => i.date.year == bucketStart.year && i.date.month == bucketStart.month;
          break;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentListScreen(
            investments: filtered.where(matchesBucket).toList(),
            subtitle: title,
          ),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BreakdownDonut(
          labels: [for (final p in topProviders) p.name, if (otherProvidersTotal > 0) 'Other'],
          keys: [for (final p in topProviders) p.key, if (otherProvidersTotal > 0) null],
          values: [
            for (final p in topProviders) p.total,
            if (otherProvidersTotal > 0) otherProvidersTotal,
          ],
          onTapKey: openProvider,
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TrendBarChart(
          dates: [for (final p in points) p.date],
          primaryValues: [for (final p in points) p.invested],
          secondaryValues: [for (final p in points) p.redeemed],
          granularity: range.trendGranularity,
          primaryLabel: 'Invested',
          secondaryLabel: 'Redeemed',
          primaryColor: scheme.primary,
          secondaryColor: const Color(0xFFF59E0B),
          onTapBucket: openBucket,
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

class _ProviderRow extends StatelessWidget {
  final _ProviderSummary provider;
  const _ProviderRow({required this.provider});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = provider;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: primary.withOpacity(0.12),
        child: Icon(Icons.account_balance_outlined, color: primary, size: 18),
      ),
      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${p.count} event${p.count == 1 ? '' : 's'}'),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.invested > 0)
            Text('-${Formatters.currency(p.invested)}', style: TextStyle(color: primary, fontSize: 12)),
          if (p.redeemed > 0)
            Text('+${Formatters.currency(p.redeemed)}',
                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentListScreen(investments: p.events, subtitle: p.name),
        ),
      ),
    );
  }
}
