import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/duplicate_detection_service.dart';
import '../services/insights_service.dart';
import '../widgets/spend_category_row.dart';
import '../widgets/ui/empty_state.dart';
import 'transaction_list_screen.dart';

/// Full "By spend category" drilldown for Insights' spend-category
/// breakdown — every [SpendCategory] with debit activity in [transactions],
/// not just the top 6 the inline section caps itself to. No search (unlike
/// [MerchantListScreen]/[InstrumentListScreen]): SpendCategory is a small
/// fixed set (~14 values), never open-ended, so there's nothing a search
/// box would usefully narrow down.
class SpendCategoryListScreen extends StatelessWidget {
  final List<Transaction> transactions;
  final String? subtitle;

  const SpendCategoryListScreen({super.key, required this.transactions, this.subtitle});

  @override
  Widget build(BuildContext context) {
    // [transactions] is a one-off snapshot from whichever Insights screen
    // pushed this route. Re-deriving a live copy from SmsProvider (matched
    // by id) and re-grouping it means a correction made to a transaction
    // deeper in a drilldown (spend category, merchant, ...) is reflected
    // here too, instead of this screen staying stale until it's popped and
    // re-opened — same as MerchantListScreen/InstrumentListScreen.
    final ids = transactions.map((t) => t.smsId).toSet();
    final liveTransactions = context.watch<SmsProvider>().transactions.where((t) => ids.contains(t.smsId)).toList();
    // Excludes duplicate-alert shadows (see duplicate_detection_service.dart)
    // so a purchase reported by two SMS doesn't double a category's total —
    // same dedup groupBySpendCategory's other callers (InsightsService) apply.
    final duplicateIds = findDuplicateTransactionIds(liveTransactions);
    final categories =
        groupBySpendCategory(liveTransactions.where((t) => !duplicateIds.contains(t.smsId)).toList());

    return Scaffold(
      appBar: AppBar(
        title: const Text('By spend category'),
        bottom: subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
      ),
      body: categories.isEmpty
          ? const EmptyState(icon: Icons.pie_chart_outline, title: 'No spend in this range')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final c = categories[index];
                return SpendCategoryRow(
                  summary: c,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionListScreen(
                        title: c.displayName,
                        subtitle: subtitle,
                        transactions: liveTransactions
                            .where((t) => t.spendCategory == c.category && t.direction == TxnDirection.debit)
                            .toList(),
                        matches: (t) => t.spendCategory == c.category && t.direction == TxnDirection.debit,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
