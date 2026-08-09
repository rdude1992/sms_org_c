import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';

/// Bulk spend-category tagging for TransactionListScreen's multi-select —
/// see SmsProvider.setSpendCategoryForTransactions. Includes an
/// "Uncategorised" option so a batch that was auto-tagged wrong can be
/// cleared in one pass too, not just set. [onApplied] fires right after the
/// category is persisted — TransactionListScreen uses it to clear its local
/// selection so the tiles un-check and drop out of selection mode instead of
/// staying checked with a category that's already been applied.
Future<void> showBulkSpendCategorySheet(
  BuildContext context,
  SmsProvider provider,
  List<int> smsIds, {
  VoidCallback? onApplied,
}) {
  return showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      void apply(SpendCategory? category) {
        Navigator.pop(sheetContext);
        provider.setSpendCategoryForTransactions(smsIds, category);
        onApplied?.call();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set category for ${smsIds.length} transaction${smsIds.length == 1 ? '' : 's'}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Uncategorised'),
              onTap: () => apply(null),
            ),
            for (final category in SpendCategory.values)
              ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                onTap: () => apply(category),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Fast, single-transaction spend-category picker — tap a category and it
/// applies immediately, no Save button, mirroring showCategoryPickerSheet's
/// SMS-category flow. Reachable directly from TransactionTile's long-press
/// menu so changing just the category doesn't require opening the full
/// "Edit transaction" form and scrolling past Type/Instrument/Merchant/
/// Wallet to reach it.
Future<void> showQuickSpendCategorySheet(
  BuildContext context,
  SmsProvider provider,
  Transaction transaction,
) {
  return showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
      void apply(SpendCategory? category) {
        Navigator.pop(sheetContext);
        provider.setSpendCategoryForTransactions([transaction.smsId], category);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Set category',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('Uncategorised'),
              trailing: transaction.spendCategory == null ? Icon(Icons.check, color: scheme.primary) : null,
              onTap: () => apply(null),
            ),
            for (final category in SpendCategory.values)
              ListTile(
                leading: Icon(category.icon, color: category.color),
                title: Text(category.label),
                trailing:
                    transaction.spendCategory == category ? Icon(Icons.check, color: scheme.primary) : null,
                onTap: () => apply(category),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Bottom sheet letting the user correct a transaction's type, instrument,
/// merchant, or wallet when TransactionParserService got it wrong — see
/// SmsProvider.updateTransaction. Opens as a StatefulWidget (rather than the
/// inline builder other sheets in this app use) because a form needs local
/// state for its fields between open and Save.
Future<void> showTransactionEditSheet(
  BuildContext context,
  SmsProvider provider,
  Transaction transaction,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TransactionEditSheet(provider: provider, transaction: transaction),
  );
}

class _TransactionEditSheet extends StatefulWidget {
  final SmsProvider provider;
  final Transaction transaction;
  const _TransactionEditSheet({required this.provider, required this.transaction});

  @override
  State<_TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<_TransactionEditSheet> {
  late TxnDirection _direction;
  late InstrumentType _instrument;
  late SpendCategory? _spendCategory;
  late final TextEditingController _merchantController;
  late final TextEditingController _walletController;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    // The segmented button below only offers Credit/Debit/Reversed (an
    // "unknown" direction isn't something a user would deliberately pick) —
    // default an unknown one to Debit so what's highlighted on open matches
    // what gets saved if the user doesn't touch this field at all.
    _direction = t.direction == TxnDirection.unknown ? TxnDirection.debit : t.direction;
    _instrument = t.instrument;
    _spendCategory = t.spendCategory;
    _merchantController = TextEditingController(text: t.merchant ?? '');
    _walletController = TextEditingController(text: t.walletType ?? '');
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(context);
    widget.provider.updateTransaction(
      widget.transaction,
      direction: _direction,
      instrument: _instrument,
      merchant: _merchantController.text,
      walletType: _walletController.text,
      spendCategory: _spendCategory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Edit transaction', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "Fix the type, instrument, or merchant if this landed in the wrong list or "
                "total, or tag a spend category — the change applies right away.",
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Text('Type', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              SegmentedButton<TxnDirection>(
                segments: const [
                  ButtonSegment(value: TxnDirection.credit, label: Text('Credit')),
                  ButtonSegment(value: TxnDirection.debit, label: Text('Debit')),
                  ButtonSegment(value: TxnDirection.reversal, label: Text('Reversed')),
                ],
                selected: {_direction},
                onSelectionChanged: (selection) => setState(() => _direction = selection.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InstrumentType>(
                value: _instrument,
                decoration: const InputDecoration(labelText: 'Instrument'),
                items: const [
                  DropdownMenuItem(value: InstrumentType.debitCard, child: Text('Debit Card')),
                  DropdownMenuItem(value: InstrumentType.creditCard, child: Text('Credit Card')),
                  DropdownMenuItem(value: InstrumentType.bankAccount, child: Text('Bank Account')),
                  DropdownMenuItem(value: InstrumentType.upi, child: Text('UPI')),
                  DropdownMenuItem(value: InstrumentType.unknown, child: Text('Other')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _instrument = v);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant',
                  hintText: 'Leave blank if none',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _walletController,
                decoration: const InputDecoration(
                  labelText: 'Wallet name',
                  hintText: 'e.g. Paytm Wallet — set to file this under Wallets',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SpendCategory?>(
                value: _spendCategory,
                decoration: const InputDecoration(labelText: 'Spend category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Uncategorised')),
                  for (final category in SpendCategory.values)
                    DropdownMenuItem(value: category, child: Text(category.label)),
                ],
                onChanged: (v) => setState(() => _spendCategory = v),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
