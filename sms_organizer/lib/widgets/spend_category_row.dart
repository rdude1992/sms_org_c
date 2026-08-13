import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';

/// One spend-category summary row — shared by Insights' "By spend category"
/// section and [SpendCategoryListScreen]'s full list, so both stay in sync
/// with a single definition. A raw Row in a Padding (like
/// TransactionTile's `compact` mode), not a ListTile — ListTile enforces a
/// minimum row height even with contentPadding/minVerticalPadding pared
/// down, which read as noticeably taller than the transaction list's own
/// compact rows sitting right above it.
class SpendCategoryRow extends StatelessWidget {
  final SpendCategorySummary summary;
  final VoidCallback onTap;
  const SpendCategoryRow({super.key, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = summary.category?.color ?? scheme.outline;
    final icon = summary.category?.icon ?? Icons.label_off_outlined;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        summary.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('(${summary.count})', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${Formatters.currency(summary.totalDebit)}',
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
