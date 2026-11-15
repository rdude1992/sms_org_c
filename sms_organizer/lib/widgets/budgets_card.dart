import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/budget_service.dart';
import '../utils/formatters.dart';

const _okColor = Color(0xFF10B981);
const _warnColor = Color(0xFFF59E0B);
const _overColor = Color(0xFFEF4444);

/// This month's budget progress on the Insights screen. With no budgets set
/// it shrinks to a single "Set a monthly budget" row, so the feature stays
/// discoverable without taking space.
class BudgetsCard extends StatelessWidget {
  /// Opens this month's transactions for a category (the Insights drilldown).
  final void Function(SpendCategory category) onOpenCategory;

  const BudgetsCard({super.key, required this.onOpenCategory});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SmsProvider>();
    final statuses = provider.currentBudgetStatuses();
    final scheme = Theme.of(context).colorScheme;

    if (statuses.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.savings_outlined),
          title: const Text('Set a monthly budget'),
          subtitle: const Text('Track spend per category and get an alert at 80% and 100%.'),
          onTap: () => showBudgetEditor(context),
        ),
      );
    }

    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Budgets · ${Formatters.monthYear(now)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(onPressed: () => showBudgetEditor(context), child: const Text('Edit')),
              ],
            ),
            Text(
              '${daysInMonth - now.day} days left in the month',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final s in statuses)
              InkWell(
                onTap: () => onOpenCategory(s.category),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                  child: _BudgetRow(status: s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final BudgetStatus status;
  const _BudgetRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = status.percent >= 100
        ? _overColor
        : status.percent >= 80
            ? _warnColor
            : _okColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(status.category.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text(
              '${Formatters.currency(status.spent)} / ${Formatters.currency(status.limit)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: status.fraction.clamp(0.0, 1.0),
            minHeight: 6,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          status.remaining >= 0
              ? '${Formatters.currency(status.remaining)} left · ${status.percent}% used'
              : '${Formatters.currency(-status.remaining)} over budget',
          style: TextStyle(fontSize: 11, color: status.remaining >= 0 ? scheme.onSurfaceVariant : _overColor),
        ),
      ],
    );
  }
}

/// Sheet listing every budgetable category with its current limit; tapping
/// one opens an amount dialog (an empty amount removes the budget).
Future<void> showBudgetEditor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, controller) => Consumer<SmsProvider>(
        builder: (ctx, provider, _) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Monthly budgets. Card-bill payments, transfers and investments aren\'t spending, '
                'so they can\'t have one.',
              ),
            ),
            for (final c in budgetableCategories)
              ListTile(
                leading: Icon(c.icon),
                title: Text(c.label),
                trailing: Text(
                  provider.budgets[c] == null ? 'Not set' : Formatters.currency(provider.budgets[c]!),
                ),
                onTap: () => _editAmount(ctx, provider, c),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _editAmount(BuildContext context, SmsProvider provider, SpendCategory category) async {
  final controller = TextEditingController(
    text: provider.budgets[category]?.toStringAsFixed(0) ?? '',
  );
  final result = await showDialog<double?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${category.label} budget'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Monthly limit'),
      ),
      actions: [
        if (provider.budgets[category] != null)
          TextButton(onPressed: () => Navigator.pop(ctx, -1.0), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return;
  if (result <= 0) {
    await provider.removeBudget(category);
  } else {
    await provider.setBudget(category, result);
  }
}
