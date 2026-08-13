import 'package:flutter/material.dart';
import '../../utils/formatters.dart';

/// Shared between the Investments dashboard's aggregate gain/loss and
/// AmcDetailScreen's per-AMC/per-holding one — green above zero, red below,
/// theme-neutral at exactly zero (an untouched holding, not literally a
/// break-even one).
const kGainColor = Color(0xFF10B981);
const kLossColor = Color(0xFFEF4444);

Color gainColorFor(double gain, ColorScheme scheme) =>
    gain > 0 ? kGainColor : (gain < 0 ? kLossColor : scheme.onSurfaceVariant);

/// Every "estimated current value" figure across Investments is only as
/// fresh as the last NAV an SMS happened to mention — there's no live
/// market feed — so every screen that shows one repeats this caveat next
/// to it rather than letting the number imply more precision than it has.
const kInvestmentEstimateNote =
    'Estimated using the most recent NAV mentioned in your messages — not live market data.';

/// "Gain/Loss" stat tile — mirrors TotalStat's shape (label over a colored
/// amount) but with a signed value and an optional trailing percentage.
class GainLossStat extends StatelessWidget {
  final double gain;
  final double? gainPct;
  const GainLossStat({super.key, required this.gain, required this.gainPct});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = gainColorFor(gain, scheme);
    final sign = gain > 0 ? '+' : '';
    final pctText = gainPct == null ? '' : ' (${gainPct! > 0 ? '+' : ''}${gainPct!.toStringAsFixed(1)}%)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Gain/Loss',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          '$sign${Formatters.currency(gain)}$pctText',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
