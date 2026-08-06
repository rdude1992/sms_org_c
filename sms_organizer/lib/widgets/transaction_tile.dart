import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'detected_sms_sheet.dart';

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
      onTap: () => _showDetails(context),
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
