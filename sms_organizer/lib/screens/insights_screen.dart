import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/filter_chip_bar.dart';
import 'instrument_list_screen.dart';
import 'investment_list_screen.dart';
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
        final summary = provider.insightsSummary(from: from, to: to);

        // Previous period of equal length, for the trend deltas — undefined
        // (and hidden) for "All time" since there's no prior window to
        // compare against.
        InsightsSummary? previousSummary;
        if (from != null) {
          final length = (to ?? now).difference(from);
          final prevTo = from;
          final prevFrom = from.subtract(length);
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

        return Scaffold(
          appBar: AppBar(title: const Text('Insights')),
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
                        : ListView(
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
                              Text('Monthly trend', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              _MonthlyChart(
                                summary: summary,
                                onTapMonth: (month) => _openDrilldown(
                                  context,
                                  title: Formatters.monthYear(month),
                                  transactions: filteredTransactions
                                      .where((t) =>
                                          t.date.year == month.year && t.date.month == month.month)
                                      .toList(),
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
                                            instruments: summary.byInstrument,
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
                              _InvestmentCard(
                                summary: summary,
                                onTap: filteredInvestments.isEmpty
                                    ? null
                                    : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => InvestmentListScreen(
                                              investments: filteredInvestments,
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
                                    child: Text('${filteredTransactions.length} total · See all'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ...filteredTransactions.take(15).map((t) => TransactionTile(transaction: t)),
                            ],
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

class _MonthlyChart extends StatelessWidget {
  final InsightsSummary summary;
  final ValueChanged<DateTime> onTapMonth;
  const _MonthlyChart({required this.summary, required this.onTapMonth});

  static const _creditColor = Color(0xFF10B981);
  static const _debitColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    if (summary.monthly.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('Not enough data yet.')));
    }
    final months = summary.monthly;
    final scheme = Theme.of(context).colorScheme;
    final maxVal = months
        .map((m) => m.credit > m.debit ? m.credit : m.debit)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxVal == 0 ? 1.0 : maxVal * 1.2;

    // However many months are in range, only label a handful of them —
    // cramming a "d MMM" string under every single point is what made the
    // old chart unreadable once the range grew past a few months.
    const maxLabels = 6;
    final labelInterval = (months.length / maxLabels).ceil().clamp(1, months.length);

    void handleTap(FlTouchEvent event, LineTouchResponse? response) {
      if (event is! FlTapUpEvent) return;
      final spots = response?.lineBarSpots;
      if (spots == null || spots.isEmpty) return;
      final idx = spots.first.x.toInt();
      if (idx < 0 || idx >= months.length) return;
      onTapMonth(months[idx].month);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            _LegendDot(color: _creditColor, label: 'Credited'),
            SizedBox(width: 16),
            _LegendDot(color: _debitColor, label: 'Debited'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: (months.length - 1).toDouble(),
              lineTouchData: LineTouchData(
                touchCallback: handleTap,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final idx = s.x.toInt();
                    if (idx < 0 || idx >= months.length) return null;
                    final isCredit = s.barIndex == 0;
                    return LineTooltipItem(
                      '${Formatters.monthYear(months[idx].month)}\n'
                      '${Formatters.currency(s.y)}',
                      TextStyle(
                        color: isCredit ? _creditColor : _debitColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                _line(months.map((m) => m.credit).toList(), _creditColor),
                _line(months.map((m) => m.debit).toList(), _debitColor),
              ],
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                      final isLast = idx == months.length - 1;
                      if (idx % labelInterval != 0 && !isLast) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          Formatters.monthYear(months[idx].month),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant.withOpacity(0.4), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _line(List<double> values, Color color) {
    return LineChartBarData(
      spots: [for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
      isCurved: true,
      curveSmoothness: 0.15,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(show: values.length <= 12),
      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.08)),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Tappable donut breakdown of spend/activity by card or account — the top
/// 6 instruments each get their own slice, with anything past that folded
/// into a single "Other" slice so the chart doesn't fragment into slivers
/// once someone has a dozen linked cards. Tapping a slice (or its legend
/// row) opens the same drilldown as tapping the row in the list below.
class _InstrumentDonut extends StatelessWidget {
  final List<InstrumentSummary> instruments;
  final List<Transaction> filteredTransactions;
  final String rangeLabel;

  const _InstrumentDonut({
    required this.instruments,
    required this.filteredTransactions,
    required this.rangeLabel,
  });

  static const _palette = [
    Color(0xFFC96442),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = instruments.take(6).toList();
    final otherTotal =
        instruments.skip(6).fold<double>(0, (a, s) => a + s.totalCredit + s.totalDebit);

    final labels = [for (final s in top) s.displayName, if (otherTotal > 0) 'Other'];
    final keys = [for (final s in top) s.key, if (otherTotal > 0) null];
    final values = [
      for (final s in top) s.totalCredit + s.totalDebit,
      if (otherTotal > 0) otherTotal,
    ];
    final grandTotal = values.fold<double>(0, (a, v) => a + v);
    if (grandTotal <= 0) return const SizedBox.shrink();

    void openFor(String? key) {
      if (key == null) return;
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
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 42,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final index = response?.touchedSection?.touchedSectionIndex;
                      if (index == null || index < 0 || index >= keys.length) return;
                      openFor(keys[index]);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < values.length; i++)
                      PieChartSectionData(
                        value: values[i],
                        color: _palette[i % _palette.length],
                        radius: 20,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Formatters.currency(grandTotal),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  ),
                  Text('total', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    onTap: keys[i] == null ? null : () => openFor(keys[i]),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                          ),
                        ),
                        Text(
                          '${(values[i] / grandTotal * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  final InstrumentSummary summary;
  final VoidCallback onTap;
  const _InstrumentRow({required this.summary, required this.onTap});

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
        summary.isLinkedAccount
            ? '${summary.typeLabel} · ${summary.count} transactions'
            : '${summary.count} transactions',
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
