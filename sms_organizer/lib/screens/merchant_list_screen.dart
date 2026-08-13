import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/duplicate_detection_service.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/search_toggle_mixin.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/row_divider.dart';
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
    // Excludes duplicate-alert shadows (see duplicate_detection_service.dart)
    // so a purchase reported by two SMS doesn't double a merchant's total.
    final duplicateIds = findDuplicateTransactionIds(liveTransactions);
    final grouped =
        groupByMerchant(liveTransactions.where((t) => !duplicateIds.contains(t.smsId)).toList());

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
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sorted.length,
              separatorBuilder: (context, _) => buildRowDivider(context),
              itemBuilder: (context, index) => _MerchantTile(
                summary: sorted[index],
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
  final VoidCallback onTap;
  const _MerchantTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        summary.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('(${summary.count})', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
        ),
      ),
    );
  }
}
