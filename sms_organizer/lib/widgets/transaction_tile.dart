import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

class TransactionTile extends StatelessWidget {
  final Transaction transaction;

  const TransactionTile({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.direction == TxnDirection.credit;
    final color = isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isCredit ? '+' : '-';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: color,
          size: 18,
        ),
      ),
      title: Text(
        transaction.merchant ?? transaction.issuer ?? _instrumentLabel(transaction.instrument),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          _instrumentLabel(transaction.instrument),
          if (transaction.instrumentRef != null) '•• ${transaction.instrumentRef}',
          Formatters.relativeOrTime(transaction.date),
        ].join('  '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '$sign${Formatters.currency(transaction.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
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
