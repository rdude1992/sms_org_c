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
    // Uncategorised + all of SpendCategory.values is ~15 rows — taller than
    // a non-scroll-controlled sheet's bounded height on most phones, which
    // would silently clip the bottom of the list (categories added later,
    // like Investment, ending up unreachable) rather than scroll to them.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
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
                ],
              ),
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
    // Same reasoning as showBulkSpendCategorySheet: ~15 rows is taller than
    // a non-scroll-controlled sheet's bounded height, which would silently
    // clip the bottom of the list instead of letting it scroll.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set category',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    transaction.merchant ?? transaction.rawBody,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Uncategorised'),
                    trailing:
                        transaction.spendCategory == null ? Icon(Icons.check, color: scheme.primary) : null,
                    onTap: () => apply(null),
                  ),
                  for (final category in SpendCategory.values)
                    ListTile(
                      leading: Icon(category.icon, color: category.color),
                      title: Text(category.label),
                      trailing: transaction.spendCategory == category
                          ? Icon(Icons.check, color: scheme.primary)
                          : null,
                      onTap: () => apply(category),
                    ),
                ],
              ),
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

/// Bottom sheet for TransactionListScreen's multi-select "Edit" action —
/// applies a correction to every transaction in [transactions] at once. See
/// SmsProvider.updateTransactionsBulk: every field here defaults to "no
/// change" (an unstarted dropdown / a blank text field) rather than
/// pre-filling one transaction's values, since a batch rarely shares a
/// single starting value for every field the way one transaction's own edit
/// sheet can assume. [onApplied] fires right after the batch is persisted —
/// TransactionListScreen uses it to clear its selection.
Future<void> showBulkTransactionEditSheet(
  BuildContext context,
  SmsProvider provider,
  List<Transaction> transactions, {
  VoidCallback? onApplied,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BulkTransactionEditSheet(
      provider: provider,
      transactions: transactions,
      onApplied: onApplied,
    ),
  );
}

class _BulkTransactionEditSheet extends StatefulWidget {
  final SmsProvider provider;
  final List<Transaction> transactions;
  final VoidCallback? onApplied;
  const _BulkTransactionEditSheet({
    required this.provider,
    required this.transactions,
    this.onApplied,
  });

  @override
  State<_BulkTransactionEditSheet> createState() => _BulkTransactionEditSheetState();
}

class _BulkTransactionEditSheetState extends State<_BulkTransactionEditSheet> {
  TxnDirection? _direction;
  InstrumentType? _instrument;
  Object? _spendCategory = keepSpendCategory;
  final _merchantController = TextEditingController();
  final _walletController = TextEditingController();

  @override
  void dispose() {
    _merchantController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(context);
    widget.provider.updateTransactionsBulk(
      widget.transactions,
      direction: _direction,
      instrument: _instrument,
      merchant: _merchantController.text,
      walletType: _walletController.text,
      spendCategory: _spendCategory,
    );
    widget.onApplied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.transactions.length;
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
              Text('Edit $count transaction${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "Only fields you change here are applied — anything left as \"No change\" "
                "or blank is left exactly as it was on each transaction.",
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<TxnDirection?>(
                value: _direction,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('No change')),
                  DropdownMenuItem(value: TxnDirection.credit, child: Text('Credit')),
                  DropdownMenuItem(value: TxnDirection.debit, child: Text('Debit')),
                  DropdownMenuItem(value: TxnDirection.reversal, child: Text('Reversed')),
                ],
                onChanged: (v) => setState(() => _direction = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InstrumentType?>(
                value: _instrument,
                decoration: const InputDecoration(labelText: 'Instrument'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('No change')),
                  DropdownMenuItem(value: InstrumentType.debitCard, child: Text('Debit Card')),
                  DropdownMenuItem(value: InstrumentType.creditCard, child: Text('Credit Card')),
                  DropdownMenuItem(value: InstrumentType.bankAccount, child: Text('Bank Account')),
                  DropdownMenuItem(value: InstrumentType.upi, child: Text('UPI')),
                  DropdownMenuItem(value: InstrumentType.unknown, child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _instrument = v),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant',
                  hintText: "Leave blank to keep each transaction's existing merchant",
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _walletController,
                decoration: const InputDecoration(
                  labelText: 'Wallet name',
                  hintText: "Leave blank to keep each transaction's existing wallet",
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Object?>(
                value: _spendCategory,
                decoration: const InputDecoration(labelText: 'Spend category'),
                items: [
                  const DropdownMenuItem(value: keepSpendCategory, child: Text('No change')),
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
                  child: Text('Apply to $count transaction${count == 1 ? '' : 's'}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
