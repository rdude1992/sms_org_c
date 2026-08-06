import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import 'transaction_list_screen.dart';

/// Segregated "Cards & Accounts" drilldown for the Insights "by card /
/// account" list — buckets [InstrumentSummary] rows into Credit Cards /
/// Debit Cards / Bank Accounts / Wallets / UPI / Other sections instead of
/// one flat list sorted purely by spend, so the instrument type detected
/// from each SMS's sender shortcode/body is easy to tell apart at a
/// glance. A row spanning a debit card and its linked bank account (same
/// issuer + last-4, see [Transaction.instrumentGroupKey]) shows up once,
/// under Debit Cards, with a "Debit Card + Bank Account" badge.
class InstrumentListScreen extends StatelessWidget {
  final List<InstrumentSummary> instruments;
  final List<Transaction> transactions;
  final String? subtitle;

  const InstrumentListScreen({
    super.key,
    required this.instruments,
    required this.transactions,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final sections = _bucket(instruments);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cards & Accounts'),
        bottom: subtitle == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ),
      ),
      body: instruments.isEmpty
          ? const Center(child: Text('No cards or accounts detected in this range.'))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final section in sections)
                  if (section.items.isNotEmpty)
                    _Section(section: section, onTapItem: (s) => _openDrilldown(context, s)),
              ],
            ),
    );
  }

  void _openDrilldown(BuildContext context, InstrumentSummary s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionListScreen(
          title: s.displayName,
          subtitle: subtitle,
          transactions: transactions.where((t) => t.instrumentGroupKey == s.key).toList(),
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
  List<_SectionData> _bucket(List<InstrumentSummary> items) {
    final creditCards = <InstrumentSummary>[];
    final debitCards = <InstrumentSummary>[];
    final bankAccounts = <InstrumentSummary>[];
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
      } else {
        other.add(s);
      }
    }

    int byTotal(InstrumentSummary a, InstrumentSummary b) =>
        (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit);
    for (final list in [creditCards, debitCards, bankAccounts, wallets, other]) {
      list.sort(byTotal);
    }

    return [
      _SectionData('Credit Cards', Icons.credit_card, const Color(0xFF8B5CF6), creditCards),
      _SectionData(
          'Debit Cards', Icons.credit_card_outlined, const Color(0xFF3B6DF5), debitCards),
      _SectionData('Bank Accounts', Icons.account_balance, const Color(0xFF10B981), bankAccounts),
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
  final ValueChanged<InstrumentSummary> onTapItem;
  const _Section({required this.section, required this.onTapItem});

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
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        ...section.items.map((s) => _InstrumentTile(summary: s, onTap: () => onTapItem(s))),
        const Divider(height: 16),
      ],
    );
  }
}

class _InstrumentTile extends StatelessWidget {
  final InstrumentSummary summary;
  final VoidCallback onTap;
  const _InstrumentTile({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
      onTap: onTap,
    );
  }
}
