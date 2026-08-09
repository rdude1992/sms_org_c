import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/search_toggle_mixin.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/sparkline.dart';
import 'transaction_list_screen.dart';

/// Full "By merchant" drilldown for the Insights merchant breakdown — a
/// flat list of every merchant with a detected name, sorted by total
/// activity (unlike [InstrumentListScreen], merchants aren't bucketed into
/// typed sections; there's no equivalent grouping to make there).
class MerchantListScreen extends StatefulWidget {
  final List<Transaction> transactions;
  final String? subtitle;

  const MerchantListScreen({
    super.key,
    required this.transactions,
    this.subtitle,
  });

  @override
  State<MerchantListScreen> createState() => _MerchantListScreenState();
}

class _MerchantListScreenState extends State<MerchantListScreen>
    with SearchToggleMixin<MerchantListScreen> {
  @override
  void dispose() {
    disposeSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [transactions] is a one-off snapshot from whichever Insights screen
    // pushed this route. Re-deriving a live copy from SmsProvider (matched
    // by id) and re-grouping it into merchant summaries means a correction
    // made to a transaction deeper in a drilldown (see TransactionTile's
    // "Edit transaction"/"Not a transaction?" actions) is reflected here
    // too, instead of this screen staying stale until it's popped and
    // re-opened.
    final ids = widget.transactions.map((t) => t.smsId).toSet();
    final liveTransactions =
        context.watch<SmsProvider>().transactions.where((t) => ids.contains(t.smsId)).toList();
    final grouped = groupByMerchant(liveTransactions);

    final trimmedQuery = query.trim().toLowerCase();
    final sorted = trimmedQuery.isEmpty
        ? grouped
        : grouped.where((s) => s.displayName.toLowerCase().contains(trimmedQuery)).toList();

    return Scaffold(
      appBar: AppBar(
        title: searchAppBarTitle('Merchants', hintText: 'Search merchants'),
        actions: searchAppBarActions(),
        bottom: isSearching || widget.subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.subtitle!,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
      ),
      body: sorted.isEmpty
          ? EmptyState(
              icon: trimmedQuery.isEmpty ? Icons.storefront_outlined : Icons.search_off_outlined,
              title: trimmedQuery.isEmpty
                  ? 'No merchants detected in this range'
                  : 'No matches for "$trimmedQuery"',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sorted.length,
              itemBuilder: (context, index) => _MerchantTile(
                summary: sorted[index],
                transactions: liveTransactions,
                onTap: () => _openDrilldown(context, sorted[index], liveTransactions),
              ),
            ),
    );
  }

  void _openDrilldown(BuildContext context, MerchantSummary s, List<Transaction> liveTransactions) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(
          title: s.displayName,
          subtitle: widget.subtitle,
          transactions: liveTransactions.where((t) => t.merchantGroupKey == s.key).toList(),
          matches: (t) => t.merchantGroupKey == s.key,
        ),
      ),
    );
  }
}

class _MerchantTile extends StatelessWidget {
  final MerchantSummary summary;
  final List<Transaction> transactions;
  final VoidCallback onTap;
  const _MerchantTile({required this.summary, required this.transactions, required this.onTap});

  /// Up to the last 10 transactions for this merchant, oldest first,
  /// signed by direction — the series the row's sparkline traces.
  List<double> get _series {
    final own = transactions.where((t) => t.merchantGroupKey == summary.key).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final recent = own.length > 10 ? own.sublist(own.length - 10) : own;
    return [
      for (final t in recent)
        if (t.direction == TxnDirection.credit)
          t.amount
        else if (t.direction == TxnDirection.debit)
          -t.amount
        else
          0.0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final trendColor =
        summary.totalDebit >= summary.totalCredit ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      leading: const Icon(Icons.storefront_outlined),
      title:
          Text(summary.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text('${summary.count} transactions', style: const TextStyle(fontSize: 11.5)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sparkline(values: _series, color: trendColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (summary.totalCredit > 0)
                Text('+${Formatters.currency(summary.totalCredit)}',
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 12)),
              if (summary.totalDebit > 0)
                Text('-${Formatters.currency(summary.totalDebit)}',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
