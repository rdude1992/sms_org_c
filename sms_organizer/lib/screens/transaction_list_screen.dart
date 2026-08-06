import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';

/// Drilldown target for Insights — shows a pre-filtered slice of
/// transactions (by direction, instrument, or month) with its own totals
/// header, rather than reproducing filter logic in every entry point.
/// Split into All/Credited/Debited tabs (swipeable, like the rest of the
/// app) so a drilldown that mixes both directions — an instrument or a
/// month — can still be narrowed down further.
class TransactionListScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Transaction> transactions;

  const TransactionListScreen({
    super.key,
    required this.title,
    required this.transactions,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));
    final credited = sorted.where((t) => t.direction == TxnDirection.credit).toList();
    final debited = sorted.where((t) => t.direction == TxnDirection.debit).toList();
    final creditTotal = credited.fold<double>(0, (a, t) => a + t.amount);
    final debitTotal = debited.fold<double>(0, (a, t) => a + t.amount);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
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
                    Tab(text: 'Credited (${credited.length})'),
                    Tab(text: 'Debited (${debited.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? const Center(child: Text('No transactions in this range.'))
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: scheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _totalChip('Credited', creditTotal, const Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _totalChip('Debited', debitTotal, const Color(0xFFEF4444)),
                        ),
                        Text(
                          '${sorted.length} txns',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TransactionListView(transactions: sorted, emptyText: 'No transactions.'),
                        _TransactionListView(
                            transactions: credited, emptyText: 'No credited transactions.'),
                        _TransactionListView(
                            transactions: debited, emptyText: 'No debited transactions.'),
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

class _TransactionListView extends StatelessWidget {
  final List<Transaction> transactions;
  final String emptyText;

  const _TransactionListView({required this.transactions, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Center(child: Text(emptyText, style: const TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => TransactionTile(transaction: transactions[index]),
    );
  }
}
