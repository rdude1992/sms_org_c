import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final Transaction transaction;

  const TransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final direction = transaction.direction;
    final isCredit = direction == TxnDirection.credit;
    final isReversal = direction == TxnDirection.reversal;

    final color = isReversal
        ? const Color(0xFF9CA3AF) // neutral grey — nets to no real effect
        : (isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final sign = isReversal ? '' : (isCredit ? '+' : '-');
    final icon = isReversal
        ? Icons.replay
        : (isCredit ? Icons.arrow_downward : Icons.arrow_upward);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 10,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Padding(
        padding: const EdgeInsets.only(bottom: 2),
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
      subtitle: Text(
        [
          if (isReversal) 'Reversed' else _instrumentLabel(transaction.instrument),
          if (transaction.instrumentRef != null) _formatRef(transaction.instrumentRef!),
          Formatters.relativeOrTime(transaction.date),
        ].join('  ·  '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '$sign${Formatters.currency(transaction.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
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
