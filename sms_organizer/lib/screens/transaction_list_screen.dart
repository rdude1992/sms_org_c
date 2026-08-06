import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_tile.dart';

/// Drilldown target for Insights — shows a pre-filtered slice of
/// transactions (by direction, instrument, or month) with its own totals
/// header, rather than reproducing filter logic in every entry point.
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
    final credit = transactions
        .where((t) => t.direction == TxnDirection.credit)
        .fold<double>(0, (a, t) => a + t.amount);
    final debit = transactions
        .where((t) => t.direction == TxnDirection.debit)
        .fold<double>(0, (a, t) => a + t.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
                        child: _totalChip('Credited', credit, const Color(0xFF10B981)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _totalChip('Debited', debit, const Color(0xFFEF4444)),
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
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, index) => TransactionTile(transaction: sorted[index]),
                  ),
                ),
              ],
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
