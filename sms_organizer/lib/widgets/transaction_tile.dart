import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import 'assign_instrument_sheet.dart';
import 'category_picker_sheet.dart';
import 'detected_sms_sheet.dart';
import 'transaction_edit_sheet.dart';

class TransactionTile extends StatelessWidget {
  final Transaction transaction;

  /// Multi-select support for TransactionListScreen's bulk spend-category
  /// action — mirrors ConversationTile's selected/selectionMode pattern.
  /// [onTap]/[onLongPress] override the tile's own detail-sheet/actions-menu
  /// behaviour while set, so a tap toggles selection instead of opening
  /// anything.
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// When set, adds a "Select" entry to the long-press actions sheet (only
  /// reachable while [onLongPress] is null, i.e. not already selecting) so
  /// multi-select is still one tap away without long-press itself having to
  /// mean "start selecting" — that would bury the sheet's other actions
  /// (Edit transaction, Assign to account, Not a transaction?) behind
  /// selection mode entirely.
  final VoidCallback? onSelectStart;

  /// Shows [_ExpandedTransactionPanel] inline below the row — the raw SMS
  /// body plus one-tap category/edit shortcuts — without needing a tap to
  /// open the detail sheet first. Driven by a list-level "expand all"
  /// toggle (see TransactionListScreen) rather than per-tile state, so
  /// scanning a whole drilldown for what each entry actually says doesn't
  /// mean opening and closing the sheet one row at a time.
  final bool expanded;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSelectStart,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final direction = transaction.direction;
    final isCredit = direction == TxnDirection.credit;
    final isReversal = direction == TxnDirection.reversal;
    final isUnknown = direction == TxnDirection.unknown;
    // Reversal and unknown-direction transactions are both excluded from
    // Insights' Credited/Debited totals (see InsightsService.build) — show
    // both in neutral grey with no +/- sign so the list doesn't visually
    // imply an amount that isn't actually counted anywhere.
    final isNeutral = isReversal || isUnknown;

    final color = isNeutral
        ? const Color(0xFF9CA3AF) // neutral grey — not counted in any total
        : (isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final sign = isNeutral ? '' : (isCredit ? '+' : '-');
    final icon = isReversal
        ? Icons.replay
        : isUnknown
            ? Icons.remove
            : (isCredit ? Icons.arrow_downward : Icons.arrow_upward);

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minVerticalPadding: 10,
          selected: selected,
          selectedTileColor: scheme.primary.withOpacity(0.06),
          onTap: onTap ?? () => _showDetails(context),
          onLongPress: onLongPress ?? () => _showActions(context),
          leading: selectionMode
              ? Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                )
              : CircleAvatar(
                  radius: 20,
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(icon, color: color, size: 18),
                ),
          title: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    transaction.merchant ??
                        transaction.walletType ??
                        transaction.issuer ??
                        _instrumentLabel(transaction.instrument),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (transaction.isOverridden) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Manually edited',
                    child:
                        Icon(Icons.edit, size: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          subtitle: Text(
            [
              if (isReversal) 'Reversed' else _instrumentLabel(transaction.instrument),
              if (transaction.instrumentRef != null) _formatRef(transaction.instrumentRef!),
              Formatters.relativeOrTime(transaction.date, includeYear: true),
              if (transaction.spendCategory != null) transaction.spendCategory!.label,
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(
            '$sign${Formatters.currency(transaction.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? _ExpandedTransactionPanel(transaction: transaction)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _showDetails(BuildContext context) {
    final t = transaction;
    final details = <MapEntry<String, String>>[
      MapEntry('Amount', Formatters.currency(t.amount)),
      MapEntry(
        'Type',
        switch (t.direction) {
          TxnDirection.credit => 'Credit',
          TxnDirection.debit => 'Debit',
          TxnDirection.reversal => 'Reversed',
          TxnDirection.unknown => 'Unknown',
        },
      ),
      MapEntry('Instrument', _instrumentLabel(t.instrument)),
      if (t.instrumentRef != null) MapEntry('Reference', _formatRef(t.instrumentRef!)),
      if (t.issuer != null) MapEntry('Issuer', t.issuer!),
      if (t.merchant != null) MapEntry('Merchant', t.merchant!),
      if (t.walletType != null) MapEntry('Wallet', t.walletType!),
      if (t.spendCategory != null) MapEntry('Spend category', t.spendCategory!.label),
      if (t.balanceAfter != null) MapEntry('Balance after', Formatters.currency(t.balanceAfter!)),
      if (t.billDueDate != null) MapEntry('Bill due', Formatters.full(t.billDueDate!)),
      if (t.vehicleNumber != null) MapEntry('Vehicle', t.vehicleNumber!),
      if (t.fastagWalletId != null) MapEntry('FASTag wallet', t.fastagWalletId!),
    ];

    showDetectedSmsSheet(
      context,
      title: t.merchant ?? t.walletType ?? t.issuer ?? _instrumentLabel(t.instrument),
      date: t.date,
      rawBody: t.rawBody,
      details: details,
      onEdit: () => showTransactionEditSheet(context, context.read<SmsProvider>(), t),
    );
  }

  /// Long-press menu. "Set category" is the fast path for the single most
  /// common correction (tap a category, applies immediately, no separate
  /// form) — see showQuickSpendCategorySheet, added specifically so this
  /// one field doesn't require opening "Edit transaction" and scrolling
  /// past Type/Instrument/Merchant/Wallet to reach it. "Edit transaction"
  /// remains for everything else, or for changing several fields at once.
  /// "Not a transaction?" is for when it shouldn't be here at all — hands
  /// off to the same category picker the message list uses, so both
  /// corrections end up going through the same override machinery.
  void _showActions(BuildContext context) {
    final provider = context.read<SmsProvider>();
    final message = provider.messageById(transaction.smsId);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Set category'),
                subtitle: Text(transaction.spendCategory?.label ?? 'Uncategorised'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showQuickSpendCategorySheet(context, provider, transaction);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit transaction'),
                subtitle: const Text('Fix the type, instrument, merchant, or wallet'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showTransactionEditSheet(context, provider, transaction);
                },
              ),
              if (transaction.instrumentRef == null)
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Assign to account'),
                  subtitle: const Text("SMS didn't name a specific account — pick one of yours"),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showAssignInstrumentSheet(context, provider, [transaction]);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Not a transaction?'),
                subtitle: Text(
                  message == null
                      ? 'Original message no longer available'
                      : 'Move it out of Transactions entirely',
                ),
                enabled: message != null,
                onTap: message == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        showCategoryPickerSheet(context, provider, message);
                      },
              ),
              if (onSelectStart != null)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Select'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onSelectStart!();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// "XX1234" -> "•• 1234"; anything else (e.g. "Pluxee Card") passes
  /// through as-is.
  String _formatRef(String ref) {
    if (RegExp(r'^XX\d+$').hasMatch(ref)) return '•• ${ref.substring(2)}';
    return ref;
  }

  String _instrumentLabel(InstrumentType type) {
    switch (type) {
      case InstrumentType.creditCard:
        return 'Credit Card';
      case InstrumentType.debitCard:
        return 'Debit Card';
      case InstrumentType.bankAccount:
        return 'Bank';
      case InstrumentType.upi:
        return 'UPI';
      case InstrumentType.unknown:
        return 'Other';
    }
  }
}

/// Inline "peek at the SMS" panel a [TransactionTile] expands to show when
/// its list's "expand all" toggle is on — the raw message body plus the two
/// most common corrections (spend category, full edit) one tap away, so
/// scanning a long drilldown for what actually happened doesn't mean
/// opening the detail sheet, closing it, and moving to the next row.
class _ExpandedTransactionPanel extends StatelessWidget {
  final Transaction transaction;
  const _ExpandedTransactionPanel({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = transaction;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                t.rawBody.isEmpty ? '(no message text)' : t.rawBody,
                style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.sell_outlined, size: 16),
                  label: Text(
                    t.spendCategory?.label ?? 'Set category',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () =>
                      showQuickSpendCategorySheet(context, context.read<SmsProvider>(), t),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit transaction',
                visualDensity: VisualDensity.compact,
                onPressed: () => showTransactionEditSheet(context, context.read<SmsProvider>(), t),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
