import '../models/transaction.dart';

/// How close together two SMS have to land to plausibly be the same
/// real-world purchase reported twice (once by the card network, once by
/// the bank account) — see [findDuplicateTransactionIds]. Also used by
/// [InstrumentSummary]'s balance tie-break in insights_service.dart, since
/// it's the same "near-simultaneous alert pair" phenomenon.
const Duration kLinkedAccountEventWindow = Duration(minutes: 5);

/// Amount-match tolerance for pairing — effectively an exact-match
/// requirement, only wide enough to absorb double-precision rounding from
/// parsed amount strings. A card-network alert and its linked bank-account
/// alert always report the identical charged amount; a mismatch means
/// they're two different purchases, not a fee/rounding difference.
const double kDuplicateAmountEpsilon = 0.01;

/// Some banks send two SMS for one purchase: a card-network alert ("used
/// your debit card for Rs X at merchant") and a bank-account debit alert
/// ("account debited Rs X"). Both parse into separate [Transaction] rows
/// that share the same [Transaction.instrumentGroupKey] (see there — a
/// debit card and its linked bank account merge into one group), but
/// without this, both get counted in Insights totals, double-counting the
/// same real spend.
///
/// Returns the [Transaction.smsId]s of the "shadow" half of each detected
/// pair — the one to exclude from aggregate totals. Never returns the
/// "primary" half, and never signals that a transaction should be deleted
/// or hidden from the raw SMS/transaction list: the user still received
/// both texts, only the double-counted financial record should be
/// suppressed from sums.
///
/// Pairing requires: same [Transaction.instrumentGroupKey], one
/// [InstrumentType.debitCard] and one [InstrumentType.bankAccount] (a
/// group missing either side has nothing to pair), both
/// [TxnDirection.debit], amounts matching within [kDuplicateAmountEpsilon],
/// and timestamps within [kLinkedAccountEventWindow]. A transaction the
/// user has manually corrected ([Transaction.isOverridden]) is trusted as
/// its own independent record: if both halves of a would-be pair are
/// overridden, the pair is left alone entirely (two independent manual
/// reviews shouldn't be silently collapsed); if only one side is
/// overridden, it's always kept as primary.
Set<int> findDuplicateTransactionIds(List<Transaction> transactions) {
  final byGroup = <String, List<Transaction>>{};
  for (final t in transactions) {
    if (t.direction != TxnDirection.debit) continue;
    byGroup.putIfAbsent(t.instrumentGroupKey, () => []).add(t);
  }

  final duplicateIds = <int>{};

  for (final group in byGroup.values) {
    final cardSide = group.where((t) => t.instrument == InstrumentType.debitCard).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final acctSide = group.where((t) => t.instrument == InstrumentType.bankAccount).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (cardSide.isEmpty || acctSide.isEmpty) continue;

    final consumedAcctIds = <int>{};
    for (final card in cardSide) {
      Transaction? bestMatch;
      Duration? bestDelta;
      for (final acct in acctSide) {
        if (consumedAcctIds.contains(acct.smsId)) continue;
        if ((acct.amount - card.amount).abs() > kDuplicateAmountEpsilon) continue;
        final delta = acct.date.difference(card.date).abs();
        if (delta > kLinkedAccountEventWindow) continue;
        if (bestDelta == null || delta < bestDelta) {
          bestMatch = acct;
          bestDelta = delta;
        }
      }
      if (bestMatch == null) continue;
      consumedAcctIds.add(bestMatch.smsId);

      final shadowId = _pickShadow(card, bestMatch);
      if (shadowId != null) duplicateIds.add(shadowId);
    }
  }

  return duplicateIds;
}

/// Returns the [Transaction.smsId] of the half of [a]/[b] to suppress from
/// totals, or null if the pair shouldn't be treated as a duplicate at all.
int? _pickShadow(Transaction a, Transaction b) {
  if (a.isOverridden && b.isOverridden) return null;
  if (a.isOverridden) return b.smsId;
  if (b.isOverridden) return a.smsId;

  if ((a.merchant != null) != (b.merchant != null)) {
    return a.merchant != null ? b.smsId : a.smsId;
  }
  if ((a.spendCategory != null) != (b.spendCategory != null)) {
    return a.spendCategory != null ? b.smsId : a.smsId;
  }
  if (a.date != b.date) {
    return a.date.isBefore(b.date) ? b.smsId : a.smsId;
  }
  return a.smsId < b.smsId ? b.smsId : a.smsId;
}
