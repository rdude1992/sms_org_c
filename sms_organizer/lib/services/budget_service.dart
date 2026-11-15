import '../models/transaction.dart';
import 'insights_service.dart' show kNonSpendCategories;

/// Alert thresholds, as percentages of a monthly budget.
const kBudgetAlertThresholds = [80, 100];

/// Categories a budget can be set on: real spending only. Card-bill
/// payments, self-transfers and investments aren't spend (see
/// kNonSpendCategories), and income is never a debit.
List<SpendCategory> get budgetableCategories => [
      for (final c in SpendCategory.values)
        if (!kNonSpendCategories.contains(c) && c != SpendCategory.income) c,
    ];

class BudgetStatus {
  final SpendCategory category;
  final double limit;
  final double spent;

  const BudgetStatus({required this.category, required this.limit, required this.spent});

  /// Share of the limit used; 1.0 = exactly at the limit.
  double get fraction => limit <= 0 ? 0 : spent / limit;
  int get percent => (fraction * 100).floor();
  double get remaining => limit - spent;
}

/// One [BudgetStatus] per budgeted category, most-used first.
/// [spentByCategory] is this month's debit total per category.
List<BudgetStatus> budgetStatuses(
  Map<SpendCategory, double> budgets,
  Map<SpendCategory, double> spentByCategory,
) {
  return [
    for (final e in budgets.entries)
      BudgetStatus(category: e.key, limit: e.value, spent: spentByCategory[e.key] ?? 0),
  ]..sort((a, b) => b.fraction.compareTo(a.fraction));
}

/// Thresholds [status] has reached that haven't been alerted yet. Only the
/// highest is worth a notification when several are crossed at once (going
/// from 50% straight to 120% should say "over budget", not also "80%").
int? thresholdToAlert(BudgetStatus status, Set<int> alreadyAlerted) {
  int? highest;
  for (final t in kBudgetAlertThresholds) {
    if (status.percent >= t && !alreadyAlerted.contains(t)) highest = t;
  }
  return highest;
}
