import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';
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
              const Divider(height: 1),
              Expanded(
                child: provider.transactions.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No transaction SMS detected yet. Once bank/card alerts arrive '
                            '(or after the first sync), spend and investment insights will show up here.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : filteredTransactions.isEmpty
                        ? const Center(child: Text('No transactions in this range.'))
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
                              Text('By card / account', style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              if (summary.byInstrument.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('No transactions in this range.',
                                      style: TextStyle(color: Colors.grey)),
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
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final r in InsightsRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(r.label),
                selected: selected == r,
                onSelected: (_) => onSelected(r),
              ),
            ),
        ],
      ),
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
                  Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
    if (previous == 0 && current == 0) {
      return const Text('No change', style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    final delta = current - previous;
    final pct = previous == 0 ? 100.0 : (delta / previous * 100).abs();
    final isUp = delta > 0;
    final isFlat = delta == 0;
    final favourable = isFlat ? null : (isUp == increaseIsGood);
    final color = isFlat
        ? Colors.grey
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  final InstrumentSummary summary;
  final VoidCallback onTap;
  const _InstrumentRow({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      minVerticalPadding: 10,
      leading: const Icon(Icons.credit_card_outlined),
      title: Text(summary.displayName),
      subtitle: Text('${summary.count} transactions'),
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
                  const Icon(Icons.trending_up, color: Color(0xFF3B6DF5)),
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
                    child: _miniStat('Invested', summary.totalInvested, const Color(0xFF3B6DF5)),
                  ),
                  Expanded(
                    child: _miniStat('Redeemed', summary.totalRedeemed, const Color(0xFFF59E0B)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.investmentEventCount} SIP / mutual fund / trade SMS detected'
                '${onTap != null ? ' · tap to view' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(Formatters.currency(value),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
