import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final summary = provider.insightsSummary();

        return Scaffold(
          appBar: AppBar(title: const Text('Insights')),
          body: provider.transactions.isEmpty
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
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TotalsRow(summary: summary),
                    const SizedBox(height: 20),
                    Text('Monthly trend', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _MonthlyChart(summary: summary),
                    const SizedBox(height: 24),
                    Text('By card / account', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...summary.byInstrument.take(6).map((s) => _InstrumentRow(summary: s)),
                    const SizedBox(height: 24),
                    _InvestmentCard(summary: summary),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
                        Text('${provider.transactions.length} total',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...provider.transactions
                        .take(15)
                        .map((t) => TransactionTile(transaction: t)),
                  ],
                ),
        );
      },
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final InsightsSummary summary;
  const _TotalsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TotalCard(
            label: 'Credited',
            value: summary.totalCredit,
            color: const Color(0xFF10B981),
            icon: Icons.arrow_downward,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TotalCard(
            label: 'Debited',
            value: summary.totalDebit,
            color: const Color(0xFFEF4444),
            icon: Icons.arrow_upward,
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _TotalCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
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
            const SizedBox(height: 8),
            Text(
              Formatters.currency(value),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final InsightsSummary summary;
  const _MonthlyChart({required this.summary});

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
  const _InstrumentRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
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
