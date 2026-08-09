import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/total_stat.dart';

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

    // [transactions] is a one-off snapshot handed down by whichever Insights
    // screen pushed this route. Re-deriving the live copy from SmsProvider
    // (matched by id, not by re-running the original filter — this screen
    // was never given one) means a correction made via a tile's "Edit
    // transaction"/"Not a transaction?" action (see TransactionTile) is
    // reflected immediately: it moves to the right Credited/Debited tab, the
    // header totals update, and a message reclassified out of Transactions
    // entirely just drops out of the list — all without backing out and
    // re-opening this drilldown.
    final ids = transactions.map((t) => t.smsId).toSet();
    final live = context.watch<SmsProvider>().transactions.where((t) => ids.contains(t.smsId)).toList();

    final sorted = [...live]..sort((a, b) => b.date.compareTo(a.date));
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
            ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'No transactions in this range')
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: scheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TotalStat(label: 'Credited', value: creditTotal, color: const Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TotalStat(label: 'Debited', value: debitTotal, color: const Color(0xFFEF4444)),
                        ),
                        Text(
                          '${sorted.length} txns',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
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
}

class _TransactionListView extends StatelessWidget {
  final List<Transaction> transactions;
  final String emptyText;

  const _TransactionListView({required this.transactions, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return EmptyState(icon: Icons.receipt_long_outlined, title: emptyText);
    }
    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) => TransactionTile(transaction: transactions[index]),
    );
  }
}
