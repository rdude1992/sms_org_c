import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import 'category_picker_sheet.dart';
import 'detected_sms_sheet.dart';
import 'investment_edit_sheet.dart';

class InvestmentTile extends StatelessWidget {
  final InvestmentEvent investment;

  const InvestmentTile({super.key, required this.investment});

  @override
  Widget build(BuildContext context) {
    final isRedemption = investment.kind.isRedemption;
    final color = isRedemption ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.primary;
    final sign = isRedemption ? '+' : '-';
    final icon = isRedemption ? Icons.call_received : Icons.trending_up;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minVerticalPadding: 10,
      onTap: () => _showDetails(context),
      onLongPress: () => _showActions(context),
      leading: CircleAvatar(
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
                investment.fundOrScheme ?? investment.amc ?? investment.kind.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (investment.isOverridden) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Manually edited',
                child: Icon(Icons.edit, size: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
      subtitle: Text(
        [
          investment.kind.label,
          Formatters.relativeOrTime(investment.date),
          if (investment.folioOrAccount != null) 'Folio ${investment.folioOrAccount}',
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

  /// Long-press menu: "Edit investment" for when it's correctly an
  /// investment but its type/fund/AMC/folio is wrong, or "Not an
  /// investment?" for when it shouldn't be here at all — the latter hands
  /// off to the same category picker the message list uses, so both
  /// corrections end up going through the same override machinery (see
  /// TransactionTile._showActions for the transaction-side equivalent).
  void _showActions(BuildContext context) {
    final provider = context.read<SmsProvider>();
    final message = provider.messageById(investment.smsId);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit investment'),
                subtitle: const Text('Fix the type, fund/scheme, AMC, or folio'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showInvestmentEditSheet(context, provider, investment);
                },
              ),
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: const Text('Not an investment?'),
                subtitle: Text(
                  message == null
                      ? 'Original message no longer available'
                      : 'Move it out of Investments entirely',
                ),
                enabled: message != null,
                onTap: message == null
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        showCategoryPickerSheet(context, provider, message);
                      },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
