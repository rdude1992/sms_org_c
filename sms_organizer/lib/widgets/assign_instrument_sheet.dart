import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';

/// Lets the user manually pin [transactions] — TransactionParserService
/// couldn't tie them to a specific account (no last-4 in the SMS at all,
/// e.g. an NEFT debit that only names the recipient: "... has been credited
/// to SK on ...") — to one of their already-detected bank accounts/cards.
/// [transactions] is almost always a single-element list, reached from one
/// TransactionTile's long-press menu; TransactionListScreen's multi-select
/// "Assign to account" action is the only caller that passes more than one.
///
/// For a single transaction, picking an account also offers to apply the
/// same assignment to other still-unassigned transactions that look like
/// they're from the same real-world sender — matched by sender address,
/// detected bank name, or (when neither SMS has one) a shared message
/// template, since the same bank's alerts can arrive under several
/// different DLT sender codes — see
/// SmsProvider.findSimilarUnassignedTransactions — but only after showing
/// exactly what would change and getting an explicit Apply tap. That
/// follow-up is skipped for a multi-transaction call: the caller already
/// hand-picked the whole batch, so guessing at further "similar" additions
/// on top of an explicit multi-select would second-guess a choice the user
/// already made.
Future<void> showAssignInstrumentSheet(
  BuildContext context,
  SmsProvider provider,
  List<Transaction> transactions, {
  VoidCallback? onApplied,
}) {
  final candidates = provider.assignableInstruments;
  final count = transactions.length;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final scheme = Theme.of(sheetContext).colorScheme;
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
                    'Assign to account',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count == 1
                        ? "This transaction's SMS didn't name a specific account — pick which of "
                            "your detected accounts it actually belongs to."
                        : "Pick which of your detected accounts these $count transactions "
                            "actually belong to.",
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  'No detected accounts yet — this shows up once at least one other '
                  'transaction has a clear account or card number.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  // Named _tileContext (not `context`) deliberately: it's
                  // scoped to a ListTile that's about to be popped away, so
                  // using it (or an accidentally-shadowed `context`) for the
                  // follow-up "apply to similar" sheet below would silently
                  // no-op once that tile is disposed. The outer [context] —
                  // the screen that opened this sheet, which outlives it —
                  // is what the follow-up flow actually needs.
                  itemBuilder: (_tileContext, index) {
                    final s = candidates[index];
                    return ListTile(
                      leading: Icon(_iconFor(s.primaryType), color: scheme.primary),
                      title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${s.typeLabel} · ${s.count} transactions'),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _assignAndOfferSimilar(context, provider, transactions, s);
                        onApplied?.call();
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _assignAndOfferSimilar(
  BuildContext context,
  SmsProvider provider,
  List<Transaction> transactions,
  InstrumentSummary target,
) async {
  await provider.assignInstrumentToTransactions(
    transactions,
    instrument: target.primaryType,
    issuer: target.issuer,
    instrumentRef: target.ref,
  );
  if (!context.mounted || transactions.length != 1) return;

  final similar = provider.findSimilarUnassignedTransactions(transactions.first);
  if (similar.isEmpty) return;

  await _showSimilarTransactionsConfirmSheet(context, provider, similar, target);
}

/// The "apply to similar messages" confirmation — every candidate starts
/// checked (the common case is "yes, all of these"), but nothing is applied
/// until the user reviews the list and taps Apply.
Future<void> _showSimilarTransactionsConfirmSheet(
  BuildContext context,
  SmsProvider provider,
  List<Transaction> similar,
  InstrumentSummary target,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _SimilarTransactionsSheet(similar: similar, target: target, provider: provider),
  );
}

class _SimilarTransactionsSheet extends StatefulWidget {
  final List<Transaction> similar;
  final InstrumentSummary target;
  final SmsProvider provider;
  const _SimilarTransactionsSheet({required this.similar, required this.target, required this.provider});

  @override
  State<_SimilarTransactionsSheet> createState() => _SimilarTransactionsSheetState();
}

class _SimilarTransactionsSheetState extends State<_SimilarTransactionsSheet> {
  late final Set<int> _checked = widget.similar.map((t) => t.smsId).toSet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    'Apply to similar transactions?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Found ${widget.similar.length} more transaction${widget.similar.length == 1 ? '' : 's'} '
                    'that look like the same sender (by address, bank name, or message '
                    'template) with no account detected — assign these to '
                    '${widget.target.displayName} too?',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.similar.length,
                itemBuilder: (context, index) {
                  final t = widget.similar[index];
                  final checked = _checked.contains(t.smsId);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (v) => setState(() {
                      if (v ?? false) {
                        _checked.add(t.smsId);
                      } else {
                        _checked.remove(t.smsId);
                      }
                    }),
                    title: Text(
                      t.merchant ?? t.rawBody,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      '${Formatters.currency(t.amount)}  ·  ${Formatters.relativeOrTime(t.date)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _checked.isEmpty
                          ? null
                          : () async {
                              final toApply =
                                  widget.similar.where((t) => _checked.contains(t.smsId)).toList();
                              Navigator.pop(context);
                              await widget.provider.assignInstrumentToTransactions(
                                toApply,
                                instrument: widget.target.primaryType,
                                issuer: widget.target.issuer,
                                instrumentRef: widget.target.ref,
                              );
                            },
                      child: Text('Apply (${_checked.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(InstrumentType type) {
  switch (type) {
    case InstrumentType.creditCard:
      return Icons.credit_card;
    case InstrumentType.debitCard:
      return Icons.credit_card_outlined;
    case InstrumentType.bankAccount:
      return Icons.account_balance_outlined;
    case InstrumentType.upi:
      return Icons.qr_code;
    case InstrumentType.unknown:
      return Icons.help_outline;
  }
}
