import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';
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
                              _InvestmentCard(summary: summary),
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

  @override
  Widget build(BuildContext context) {
    if (summary.monthly.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('Not enough data yet.')));
    }
    final months = summary.monthly;
    final maxVal = months
        .map((m) => m.credit > m.debit ? m.credit : m.debit)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxVal == 0 ? 1 : maxVal * 1.2,
          barTouchData: BarTouchData(
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent) return;
              final idx = response?.spot?.touchedBarGroupIndex;
              if (idx == null || idx < 0 || idx >= months.length) return;
              onTapMonth(months[idx].month);
            },
          ),
          barGroups: [
            for (int i = 0; i < months.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(toY: months[i].credit, color: const Color(0xFF10B981), width: 8),
                  BarChartRodData(toY: months[i].debit, color: const Color(0xFFEF4444), width: 8),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      Formatters.monthYear(months[idx].month),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
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
  const _InvestmentCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.trending_up, color: Color(0xFF3B6DF5)),
                SizedBox(width: 8),
                Text('Investments', style: TextStyle(fontWeight: FontWeight.bold)),
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
              '${summary.investmentEventCount} SIP / mutual fund / trade SMS detected',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
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
