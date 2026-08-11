import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/ui/empty_state.dart';
import 'transaction_list_screen.dart';

/// Groups every still-Uncategorised transaction by merchant (or, for the
/// merchant-less ones, by normalised SMS template — see
/// [Transaction.categoryReviewGroupKey]) so a batch of transactions from
/// the same real-world sender can be tagged in one tap via
/// [showBulkSpendCategorySheet], instead of one at a time. Tagging a group
/// also teaches SmsProvider that merchant's category going forward (see
/// SmsProvider._rememberMerchantCategory) — this is the actual point:
/// what makes an uncategorised backlog tractable isn't tagging every
/// transaction, it's tagging every *merchant* once.
class UncategorisedReviewScreen extends StatelessWidget {
  const UncategorisedReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uncategorised =
        context.watch<SmsProvider>().transactions.where((t) => t.spendCategory == null).toList();

    if (uncategorised.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review uncategorised')),
        body: const EmptyState(
          icon: Icons.check_circle_outline,
          title: 'Nothing to review',
          message: 'Every transaction has a spend category.',
        ),
      );
    }

    final groups = <String, List<Transaction>>{};
    for (final t in uncategorised) {
      groups.putIfAbsent(t.categoryReviewGroupKey, () => []).add(t);
    }
    final sortedGroups = groups.values.toList()
      // Biggest groups first — tagging these first clears the most
      // transactions (and future ones, once the merchant is learned) per
      // tap, so the backlog shrinks fastest.
      ..sort((a, b) => b.length.compareTo(a.length));

    final totalAmount = uncategorised.fold<double>(0, (sum, t) => sum + t.amount);

    return Scaffold(
      appBar: AppBar(title: Text('Review uncategorised (${uncategorised.length})')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: scheme.surfaceVariant.withOpacity(0.4),
            child: Text(
              '${uncategorised.length} transaction${uncategorised.length == 1 ? '' : 's'} '
              '(${Formatters.currency(totalAmount)}) across ${sortedGroups.length} '
              'group${sortedGroups.length == 1 ? '' : 's'} — tap one to tag the whole group at once.',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sortedGroups.length,
              itemBuilder: (context, index) => _GroupRow(group: sortedGroups[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final List<Transaction> group;
  const _GroupRow({required this.group});

  String get _title {
    final first = group.first;
    if (first.merchant != null) return first.merchant!;
    if (first.walletType != null) return first.walletType!;
    if (first.issuer != null) return '${first.issuer} transfer';
    final body = first.rawBody.trim();
    return body.length > 60 ? '${body.substring(0, 60)}…' : body;
  }

  /// Opens the group's transactions in the same drilldown Insights uses —
  /// [TransactionListScreen] already gives full raw-SMS content per row
  /// (via the detail sheet / inline expand) plus search, sort, and a
  /// multi-select "Set category" action, so previewing a group before
  /// tagging it doesn't need a separate list built just for this screen.
  /// [matches] is re-checked against live transactions, so a row tagged
  /// from inside this drilldown drops out immediately instead of lingering.
  void _viewTransactions(BuildContext context) {
    final key = group.first.categoryReviewGroupKey;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(
          title: _title,
          subtitle: 'Uncategorised · tap Select all + Set category to tag them all at once',
          transactions: group,
          matches: (t) => t.spendCategory == null && t.categoryReviewGroupKey == key,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = group.fold<double>(0, (sum, t) => sum + t.amount);
    return ListTile(
      leading: const Icon(Icons.label_off_outlined),
      title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${group.length} transaction${group.length == 1 ? '' : 's'}',
        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Formatters.currency(total),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18),
            tooltip: 'View transactions',
            visualDensity: VisualDensity.compact,
            onPressed: () => _viewTransactions(context),
          ),
        ],
      ),
      onTap: () => showBulkSpendCategorySheet(
        context,
        context.read<SmsProvider>(),
        group.map((t) => t.smsId).toList(),
      ),
    );
  }
}
