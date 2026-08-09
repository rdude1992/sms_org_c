import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';

/// Bottom sheet letting the user correct an investment's kind, fund/scheme,
/// AMC, or folio when TransactionParserService got it wrong — see
/// SmsProvider.updateInvestment. Opens as a StatefulWidget (rather than the
/// inline builder other sheets in this app use) because a form needs local
/// state for its fields between open and Save.
Future<void> showInvestmentEditSheet(
  BuildContext context,
  SmsProvider provider,
  InvestmentEvent investment,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _InvestmentEditSheet(provider: provider, investment: investment),
  );
}

class _InvestmentEditSheet extends StatefulWidget {
  final SmsProvider provider;
  final InvestmentEvent investment;
  const _InvestmentEditSheet({required this.provider, required this.investment});

  @override
  State<_InvestmentEditSheet> createState() => _InvestmentEditSheetState();
}

class _InvestmentEditSheetState extends State<_InvestmentEditSheet> {
  late InvestmentKind _kind;
  late final TextEditingController _fundController;
  late final TextEditingController _amcController;
  late final TextEditingController _folioController;

  @override
  void initState() {
    super.initState();
    final i = widget.investment;
    _kind = i.kind;
    _fundController = TextEditingController(text: i.fundOrScheme ?? '');
    _amcController = TextEditingController(text: i.amc ?? '');
    _folioController = TextEditingController(text: i.folioOrAccount ?? '');
  }

  @override
  void dispose() {
    _fundController.dispose();
    _amcController.dispose();
    _folioController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(context);
    widget.provider.updateInvestment(
      widget.investment,
      kind: _kind,
      fundOrScheme: _fundController.text,
      amc: _amcController.text,
      folioOrAccount: _folioController.text,
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
              Text('Edit investment', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "Fix the type, fund, or AMC if this landed in the wrong list or "
                "provider bucket — the change applies right away.",
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<InvestmentKind>(
                value: _kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final kind in InvestmentKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _kind = v);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _fundController,
                decoration: const InputDecoration(
                  labelText: 'Fund / Scheme',
                  hintText: 'Leave blank if none',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amcController,
                decoration: const InputDecoration(
                  labelText: 'AMC',
                  hintText: 'e.g. Axis MF — sets which provider bucket this is filed under',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _folioController,
                decoration: const InputDecoration(
                  labelText: 'Folio / Account',
                  hintText: 'Leave blank if none',
                ),
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
