import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/investment_tile.dart';

/// Drilldown target for the Insights "Investments" card — mirrors
/// TransactionListScreen's All/split-direction tab pattern, split here into
/// All/Invested/Redeemed since that's the distinction InvestmentKind draws.
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

    return DefaultTabController(
      length: 3,
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
                  tabs: [
                    Tab(text: 'All (${sorted.length})'),
                    Tab(text: 'Invested (${invested.length})'),
                    Tab(text: 'Redeemed (${redeemed.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? const Center(child: Text('No investment activity in this range.'))
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: scheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _totalChip('Invested', investedTotal, const Color(0xFF3B6DF5)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _totalChip('Redeemed', redeemedTotal, const Color(0xFFF59E0B)),
                        ),
                        Text(
                          '${sorted.length} events',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _InvestmentListView(investments: sorted, emptyText: 'No investment activity.'),
                        _InvestmentListView(investments: invested, emptyText: 'Nothing invested.'),
                        _InvestmentListView(investments: redeemed, emptyText: 'Nothing redeemed.'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _totalChip(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(
          Formatters.currency(value),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
        ),
      ],
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
      return Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: investments.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => InvestmentTile(investment: investments[index]),
    );
  }
}
