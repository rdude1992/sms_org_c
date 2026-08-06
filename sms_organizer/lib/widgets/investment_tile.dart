import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import 'detected_sms_sheet.dart';

class InvestmentTile extends StatelessWidget {
  final InvestmentEvent investment;

  const InvestmentTile({super.key, required this.investment});

  @override
  Widget build(BuildContext context) {
    final isRedemption = investment.kind.isRedemption;
    final color = isRedemption ? const Color(0xFFF59E0B) : const Color(0xFF3B6DF5);
    final sign = isRedemption ? '+' : '-';
    final icon = isRedemption ? Icons.call_received : Icons.trending_up;

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
          investment.fundOrScheme ?? investment.amc ?? investment.kind.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      subtitle: Text(
        [investment.kind.label, Formatters.relativeOrTime(investment.date)].join('  ·  '),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '$sign${Formatters.currency(investment.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final i = investment;
    final details = <MapEntry<String, String>>[
      MapEntry('Amount', Formatters.currency(i.amount)),
      MapEntry('Type', i.kind.label),
      if (i.fundOrScheme != null) MapEntry('Fund / Scheme', i.fundOrScheme!),
      if (i.amc != null) MapEntry('AMC', i.amc!),
      if (i.folioOrAccount != null) MapEntry('Folio / Account', i.folioOrAccount!),
      if (i.units != null) MapEntry('Units', i.units!.toStringAsFixed(3)),
      if (i.nav != null) MapEntry('NAV', Formatters.currencyPrecise(i.nav!)),
    ];

    showDetectedSmsSheet(
      context,
      title: i.fundOrScheme ?? i.amc ?? i.kind.label,
      date: i.date,
      rawBody: i.rawBody,
      details: details,
    );
  }
}
