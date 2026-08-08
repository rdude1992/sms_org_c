import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../utils/formatters.dart';

/// Tappable donut + legend breakdown of pre-bucketed slices — shared by
/// every Insights/Investments section that needs a "top N slices + Other"
/// pie chart with a tap-to-drill legend (by card/account, by merchant, by
/// AMC), just fed from different data. [keys] entries of `null` render as
/// an untappable "Other" slice.
class BreakdownDonut extends StatelessWidget {
  final List<String> labels;
  final List<String?> keys;
  final List<double> values;
  final ValueChanged<String> onTapKey;

  const BreakdownDonut({
    super.key,
    required this.labels,
    required this.keys,
    required this.values,
    required this.onTapKey,
  });

  static const _palette = [
    Color(0xFFC96442),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEF4444),
    Color(0xFF06B6D4),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grandTotal = values.fold<double>(0, (a, v) => a + v);
    if (grandTotal <= 0) return const SizedBox.shrink();

    void openFor(String? key) {
      if (key != null) onTapKey(key);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 42,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final index = response?.touchedSection?.touchedSectionIndex;
                      if (index == null || index < 0 || index >= keys.length) return;
                      openFor(keys[index]);
                    },
                  ),
                  sections: [
                    for (var i = 0; i < values.length; i++)
                      PieChartSectionData(
                        value: values[i],
                        color: _palette[i % _palette.length],
                        radius: 20,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Formatters.currency(grandTotal),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
                  ),
                  Text('total', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    onTap: keys[i] == null ? null : () => openFor(keys[i]),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                          ),
                        ),
                        Text(
                          '${(values[i] / grandTotal * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
