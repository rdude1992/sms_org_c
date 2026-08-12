import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/duplicate_detection_service.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/search_toggle_mixin.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/sparkline.dart';
import 'transaction_list_screen.dart';

/// Segregated "Cards & Accounts" drilldown for the Insights "by card /
/// account" list — buckets [InstrumentSummary] rows into Credit Cards /
/// Debit Cards / Bank Accounts / Investments / Wallets / UPI / Other
/// sections instead of one flat list sorted purely by spend, so the
/// instrument type detected
/// from each SMS's sender shortcode/body is easy to tell apart at a
/// glance. A row spanning a debit card and its linked bank account (same
/// issuer + last-4, see [Transaction.instrumentGroupKey]) shows up once,
/// under Debit Cards, with a "Debit Card + Bank Account" badge.
///
/// [transactions] is an optional pre-filtered snapshot from whichever
/// screen pushed this route (e.g. the Insights "See all" drilldown); when
/// null (the standalone Accounts tab entry point), every live transaction
/// is shown unfiltered.
class InstrumentListScreen extends StatefulWidget {
  final List<Transaction>? transactions;
  final String? subtitle;

  const InstrumentListScreen({
    super.key,
    this.transactions,
    this.subtitle,
  });

  @override
  State<InstrumentListScreen> createState() => _InstrumentListScreenState();
}

class _InstrumentListScreenState extends State<InstrumentListScreen>
    with SearchToggleMixin<InstrumentListScreen> {
  @override
  void dispose() {
    disposeSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [transactions] is a one-off snapshot from whichever Insights screen
    // pushed this route, or null when opened as the standalone Accounts tab
    // (see the class doc). Re-deriving a live copy from SmsProvider (matched
    // by id when a snapshot was given) and re-grouping it into instrument
    // summaries means a correction made to a transaction deeper in a
    // drilldown (see TransactionTile's "Edit transaction"/"Not a
    // transaction?" actions) is reflected here too, instead of this screen
    // staying stale until it's popped and re-opened.
    final ids = widget.transactions?.map((t) => t.smsId).toSet();
    final allLive = context.watch<SmsProvider>().transactions;
    final liveTransactions = ids == null ? allLive : allLive.where((t) => ids.contains(t.smsId)).toList();
    final duplicateIds = findDuplicateTransactionIds(liveTransactions);
    final grouped = groupByInstrument(liveTransactions, duplicateIds: duplicateIds);

    final trimmedQuery = query.trim().toLowerCase();
    final instruments = trimmedQuery.isEmpty
        ? grouped
        : grouped.where((s) => s.displayName.toLowerCase().contains(trimmedQuery)).toList();
    final sections = _bucket(context, instruments);

    return Scaffold(
      appBar: AppBar(
        title: searchAppBarTitle('Cards & Accounts', hintText: 'Search cards & accounts'),
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
      body: instruments.isEmpty
          ? EmptyState(
              icon: trimmedQuery.isEmpty ? Icons.credit_card_off_outlined : Icons.search_off_outlined,
              title: trimmedQuery.isEmpty
                  ? 'No cards or accounts detected in this range'
                  : 'No matches for "$trimmedQuery"',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final section in sections)
                  if (section.items.isNotEmpty)
                    _Section(
                      section: section,
                      transactions: liveTransactions,
                      duplicateIds: duplicateIds,
                      onTapItem: (s) => _openDrilldown(context, s, liveTransactions),
                    ),
              ],
            ),
    );
  }

  void _openDrilldown(BuildContext context, InstrumentSummary s, List<Transaction> liveTransactions) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(
          title: s.displayName,
          subtitle: widget.subtitle,
          transactions: liveTransactions.where((t) => t.instrumentGroupKey == s.key).toList(),
          matches: (t) => t.instrumentGroupKey == s.key,
        ),
      ),
    );
  }

  /// A wallet-tagged group always goes under Wallets regardless of its
  /// underlying [InstrumentType]; otherwise a merged debit-card+bank
  /// group is filed under Debit Cards since that's the more specific,
  /// user-facing instrument — the linked account is surfaced via the
  /// badge rather than a section of its own.
  ///
  /// UPI isn't a section of its own — it's a payment rail, not an
  /// instrument, and virtually all UPI activity now classifies as
  /// whichever bank account/card it actually moved money through (see
  /// [TransactionParserService._instrumentType]). Anything that still
  /// lands as [InstrumentType.upi] (a bare VPA mention with no account or
  /// card context at all) falls into Other rather than getting its own
  /// section for what should be a rare edge case.
  List<_SectionData> _bucket(BuildContext context, List<InstrumentSummary> items) {
    final creditCards = <InstrumentSummary>[];
    final debitCards = <InstrumentSummary>[];
    final bankAccounts = <InstrumentSummary>[];
    final investments = <InstrumentSummary>[];
    final wallets = <InstrumentSummary>[];
    final other = <InstrumentSummary>[];

    for (final s in items) {
      if (s.walletType != null) {
        wallets.add(s);
      } else if (s.isCreditCard) {
        creditCards.add(s);
      } else if (s.isDebitCard) {
        debitCards.add(s);
      } else if (s.isBankAccount) {
        bankAccounts.add(s);
      } else if (s.isInvestment) {
        investments.add(s);
      } else {
        other.add(s);
      }
    }

    int byTotal(InstrumentSummary a, InstrumentSummary b) =>
        (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit);
    for (final list in [creditCards, debitCards, bankAccounts, investments, wallets, other]) {
      list.sort(byTotal);
    }

    return [
      _SectionData('Credit Cards', Icons.credit_card, const Color(0xFF8B5CF6), creditCards),
      _SectionData(
          'Debit Cards', Icons.credit_card_outlined, Theme.of(context).colorScheme.primary, debitCards),
      _SectionData('Bank Accounts', Icons.account_balance, const Color(0xFF10B981), bankAccounts),
      _SectionData('Investments', Icons.trending_up, const Color(0xFF6366F1), investments),
      _SectionData(
          'Wallets', Icons.account_balance_wallet_outlined, const Color(0xFFF59E0B), wallets),
      _SectionData('Other', Icons.help_outline, const Color(0xFF9CA3AF), other),
    ];
  }
}

class _SectionData {
  final String title;
  final IconData icon;
  final Color color;
  final List<InstrumentSummary> items;
  _SectionData(this.title, this.icon, this.color, this.items);
}

class _Section extends StatelessWidget {
  final _SectionData section;
  final List<Transaction> transactions;
  final Set<int> duplicateIds;
  final ValueChanged<InstrumentSummary> onTapItem;
  const _Section({
    required this.section,
    required this.transactions,
    required this.duplicateIds,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final total = section.items.fold<double>(0, (a, s) => a + s.totalCredit + s.totalDebit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Icon(section.icon, size: 16, color: section.color),
              const SizedBox(width: 8),
              Text(
                '${section.title} (${section.items.length})',
                style: TextStyle(fontWeight: FontWeight.bold, color: section.color, fontSize: 13),
              ),
              const Spacer(),
              Text(Formatters.currency(total),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        ...section.items.map(
          (s) => _InstrumentTile(
            summary: s,
            transactions: transactions,
            duplicateIds: duplicateIds,
            onTap: () => onTapItem(s),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _InstrumentTile extends StatelessWidget {
  final InstrumentSummary summary;
  final List<Transaction> transactions;
  final Set<int> duplicateIds;
  final VoidCallback onTap;
  const _InstrumentTile({
    required this.summary,
    required this.transactions,
    required this.duplicateIds,
    required this.onTap,
  });

  /// Up to the last 10 transactions for this instrument, oldest first,
  /// signed by direction — the series the row's sparkline traces. Excludes
  /// duplicate-alert shadows so one purchase reported by two SMS doesn't
  /// draw as a doubled dip.
  List<double> get _series {
    final own = transactions
        .where((t) => t.instrumentGroupKey == summary.key && !duplicateIds.contains(t.smsId))
        .toList()
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
      title: Text(summary.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        summary.isLinkedAccount
            ? '${summary.typeLabel} · ${summary.count} txns'
            : '${summary.count} transactions',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Sparkline(values: _series, color: trendColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('+${Formatters.currency(summary.totalCredit)}',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 12)),
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
