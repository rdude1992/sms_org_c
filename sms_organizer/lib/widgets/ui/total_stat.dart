import 'package:flutter/material.dart';
import '../../utils/formatters.dart';

/// Small "label over amount" stat used in drilldown headers (credited vs
/// debited, invested vs redeemed) — factored out of
/// TransactionListScreen/InvestmentListScreen, which both had their own
/// identical copy of this.
class TotalStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const TotalStat({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          Formatters.currency(value),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
