import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/holdings_service.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/ui/collapsible_section.dart';
import '../widgets/ui/filter_chip_bar.dart';
import '../widgets/ui/gain_loss_stat.dart';
import '../widgets/ui/total_stat.dart';
import '../widgets/ui/trend_line_chart.dart';
import 'investment_list_screen.dart';

/// One AMC/broker's own drilldown — reached by tapping a provider row or
/// donut slice in the "By AMC" tab. Unlike that tab (which just filters a
/// flat list of raw events), this reconstructs per-fund holdings (see
/// holdings_service.dart) to show NAV/units history, an invested-vs-
/// estimated-current-value trend, and detected SIP cadence — all "as of the
/// last SMS that mentioned it", since there's no live market feed.
class AmcDetailScreen extends StatefulWidget {
  final String providerKey;
  final String providerName;

  /// The AMC's full, unscoped event history — the range picker below only
  /// zooms the trend charts' x-axis window; headline stats (units held,
  /// current value, gain) always reflect the true current position built
  /// from every event, not just whatever's inside the selected window.
  final List<InvestmentEvent> allInvestments;

  const AmcDetailScreen({
    super.key,
    required this.providerKey,
    required this.providerName,
    required this.allInvestments,
  });

  @override
  State<AmcDetailScreen> createState() => _AmcDetailScreenState();
}

class _AmcDetailScreenState extends State<AmcDetailScreen> {
  InvestmentRange _range = InvestmentRange.allTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final providerEvents =
        widget.allInvestments.where((i) => i.providerGroupKey == widget.providerKey).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final holdings = computeFundHoldings(providerEvents);
    final totalInvested = holdings.fold<double>(0, (a, h) => a + h.netInvested);
    final totalValue = holdings.fold<double>(0, (a, h) => a + h.estimatedValue);
    final totalGain = totalValue - totalInvested;
    final totalGainPct = totalInvested <= 0 ? null : (totalGain / totalInvested) * 100;

    final now = DateTime.now();
    final (from, to) = _range.boundsFrom(now);
    bool inRange(DateTime d) {
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to)) return false;
      return true;
    }

    final valueTrend = buildValueTrend(holdings, _range.trendGranularity, from, to);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.providerName),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'All transactions',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InvestmentListScreen(
                  investments: providerEvents,
                  allInvestments: widget.allInvestments,
                  subtitle: widget.providerName,
                  initialTabIndex: 3,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: scheme.surfaceVariant.withOpacity(0.4),
            child: Row(
              children: [
                Expanded(child: TotalStat(label: 'Invested', value: totalInvested, color: scheme.primary)),
                const SizedBox(width: 12),
                Expanded(
                  child: TotalStat(label: 'Est. current value', value: totalValue, color: scheme.onSurface),
                ),
                const SizedBox(width: 12),
                Expanded(child: GainLossStat(gain: totalGain, gainPct: totalGainPct)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child:
                Text(kInvestmentEstimateNote, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 8),
          FilterChipBar<InvestmentRange>(
            values: InvestmentRange.values,
            selected: _range,
            labelBuilder: (r) => r.label,
            onSelected: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TrendLineChart(
              dates: [for (final p in valueTrend) p.date],
              series: [
                TrendLineSeries(
                  label: 'Invested',
                  color: scheme.primary,
                  values: [for (final p in valueTrend) p.invested],
                ),
                TrendLineSeries(
                  label: 'Est. value',
                  color: kGainColor,
                  values: [for (final p in valueTrend) p.value],
                ),
              ],
              axisLabelBuilder: (d) => _axisLabel(d, _range.trendGranularity),
              tooltipDateBuilder: (d) => _bucketLabel(d, _range.trendGranularity),
              valueFormatter: Formatters.currency,
              axisValueFormatter: Formatters.compactCurrency,
            ),
          ),
          const SizedBox(height: 8),
          for (final holding in holdings)
            _HoldingSection(
              key: ValueKey(holding.key),
              holding: holding,
              inRange: inRange,
              allInvestments: widget.allInvestments,
            ),
        ],
      ),
    );
  }
}

String _bucketLabel(DateTime date, TrendGranularity granularity) {
  switch (granularity) {
    case TrendGranularity.day:
      return Formatters.dayOnly(date);
    case TrendGranularity.week:
      return Formatters.dayMonth(date);
    case TrendGranularity.month:
      return Formatters.monthYear(date);
  }
}

String _axisLabel(DateTime date, TrendGranularity granularity) {
  switch (granularity) {
    case TrendGranularity.day:
      return Formatters.dayOnly(date);
    case TrendGranularity.week:
      return Formatters.dayMonth(date);
    case TrendGranularity.month:
      return Formatters.monthYearShort(date);
  }
}

/// One fund/folio holding's own card — NAV/units history plus SIP
/// detection — within an AMC that may hold more than one distinct fund or
/// folio. [inRange] only crops the two per-holding trend charts to the
/// AMC-level range picker's window; the headline stats above them always
/// reflect the holding's full history (see AmcDetailScreen).
class _HoldingSection extends StatelessWidget {
  final FundHolding holding;
  final bool Function(DateTime) inRange;

  /// Passed straight through to the pushed screen (see
  /// InvestmentListScreen.allInvestments) when the fund name is tapped, so
  /// its own "By AMC" tab keeps access to the true unscoped dataset.
  final List<InvestmentEvent> allInvestments;

  const _HoldingSection({
    super.key,
    required this.holding,
    required this.inRange,
    required this.allInvestments,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sip = detectSip(holding);
    final navPoints = navHistory(holding).where((p) => inRange(p.date)).toList();
    final unitsPoints = unitsHistory(holding).where((p) => inRange(p.date)).toList();
    final valuationPoints = holding.valuations.where((v) => inRange(v.date)).toList();

    void openHoldingTransactions() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvestmentListScreen(
              investments: holding.events,
              allInvestments: allInvestments,
              subtitle: holding.displayName,
              initialTabIndex: 3,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: scheme.outlineVariant.withOpacity(0.5)),
          const SizedBox(height: 8),
          CollapsibleSection(
            // A fund/folio can be renamed by an AMC and reappear under a new
            // holding.key (see holdings_service.dart) — accepted here since
            // that's rare and the persisted state simply starts fresh for
            // it, same as any other never-before-seen prefKey.
            prefKey: 'amc_holding.${holding.key}',
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    holding.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (sip?.isDiscontinued ?? false) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kLossColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'DISCONTINUED',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: kLossColor),
                    ),
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              tooltip: 'All transactions',
              onPressed: openHoldingTransactions,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (holding.folioOrAccount != null && holding.folioOrAccount!.trim().isNotEmpty)
                  Text('Folio ${holding.folioOrAccount}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child:
                          TotalStat(label: 'Invested', value: holding.netInvested, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TotalStat(
                          label: 'Est. value', value: holding.estimatedValue, color: scheme.onSurface),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: GainLossStat(gain: holding.estimatedGain, gainPct: holding.estimatedGainPct)),
                  ],
                ),
                const SizedBox(height: 6),
                // Some holdings (NPS Voluntary contribution SMS, notably)
                // never state units/NAV at all — skip this line rather than
                // showing a meaningless "0 units held" for them.
                if (holding.unitsHeld > 0 || holding.latestNav != null)
                  Text(
                    '${Formatters.units(holding.unitsHeld)} units held'
                    '${holding.latestNav != null ? ' · NAV ${Formatters.currencyPrecise(holding.latestNav!)}' : ''}'
                    '${holding.latestNavDate != null ? ' as of ${Formatters.dayMonthYear(holding.latestNavDate!)}' : ''}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                // Value statements (e.g. NPS "Investment value ... is Rs X")
                // are what estimatedValue actually anchors to for a holding
                // like this — see holdings_service.dart's valueAsOf — so
                // show where that figure came from rather than leaving it
                // looking like a plain units×NAV estimate.
                if (holding.latestValuation != null)
                  Text(
                    'Confirmed value ${Formatters.currency(holding.latestValuation!.value)} '
                    'as on ${Formatters.dayMonthYear(holding.latestValuation!.date)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                if (sip == null)
                  Text(
                    'No recurring monthly pattern detected.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  )
                else ...[
                  Text(
                    'Monthly SIP ${Formatters.currency(sip.amount)} · live since ${Formatters.dayMonthYear(sip.since)} '
                    '(${sip.installments} installments)',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (sip.isDiscontinued)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_circle_outline, size: 13, color: kLossColor),
                          const SizedBox(width: 4),
                          Text(
                            'SIP likely discontinued — no installment since '
                            '${Formatters.dayMonthYear(sip.lastInstallment)}',
                            style: TextStyle(fontSize: 12, color: kLossColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
                if (valuationPoints.length >= 2) ...[
                  const SizedBox(height: 12),
                  Text('Confirmed value over time',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  const SizedBox(height: 6),
                  TrendLineChart(
                    dates: [for (final p in valuationPoints) p.date],
                    series: [
                      TrendLineSeries(
                        label: 'Value',
                        color: scheme.primary,
                        values: [for (final p in valuationPoints) p.value],
                      ),
                    ],
                    axisLabelBuilder: (d) => Formatters.dayMonth(d),
                    tooltipDateBuilder: (d) => Formatters.dayMonthYear(d),
                    valueFormatter: Formatters.currency,
                    emptyMessage: 'No confirmed value history yet.',
                  ),
                ],
                const SizedBox(height: 12),
                Text('NAV over time',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 6),
                TrendLineChart(
                  dates: [for (final p in navPoints) p.date],
                  series: [
                    TrendLineSeries(
                      label: 'NAV',
                      color: scheme.primary,
                      values: [for (final p in navPoints) p.nav],
                    ),
                  ],
                  axisLabelBuilder: (d) => Formatters.dayMonth(d),
                  tooltipDateBuilder: (d) => Formatters.dayMonthYear(d),
                  valueFormatter: Formatters.currencyPrecise,
                  emptyMessage: 'No NAV history yet.',
                ),
                const SizedBox(height: 12),
                Text('Units over time',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 6),
                TrendLineChart(
                  dates: [for (final p in unitsPoints) p.date],
                  series: [
                    TrendLineSeries(
                      label: 'Units',
                      color: const Color(0xFF8B5CF6),
                      values: [for (final p in unitsPoints) p.units],
                    ),
                  ],
                  axisLabelBuilder: (d) => Formatters.dayMonth(d),
                  tooltipDateBuilder: (d) => Formatters.dayMonthYear(d),
                  valueFormatter: Formatters.units,
                  emptyMessage: 'No unit history yet.',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
