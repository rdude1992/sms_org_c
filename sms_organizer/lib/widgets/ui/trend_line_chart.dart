import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One line's worth of data for [TrendLineChart] — index-aligned with the
/// chart's shared [TrendLineChart.dates].
class TrendLineSeries {
  final String label;
  final Color color;
  final List<double> values;
  const TrendLineSeries({required this.label, required this.color, required this.values});
}

/// General-purpose 1-or-2-line trend chart — used for "Invested vs
/// Estimated value", NAV-over-time, and units-over-time. Doesn't share
/// TrendBarChart's stacked-bar shape or its "Avg X per bucket" caption:
/// NAV/units points sit at whatever real dates an SMS happened to state
/// one, not evenly bucketed ones, so an average-per-bucket figure would be
/// meaningless here. Callers own their own axis/tooltip/value formatting
/// since the three use cases above want currency, precise NAV, and plain
/// unit-count formatting respectively.
class TrendLineChart extends StatelessWidget {
  final List<DateTime> dates;
  final List<TrendLineSeries> series;
  final String Function(DateTime) axisLabelBuilder;
  final String Function(DateTime) tooltipDateBuilder;
  final String Function(double) valueFormatter;

  /// Defaults to [valueFormatter] — split out only because the y-axis
  /// sometimes wants a more compact form than the tooltip does.
  final String Function(double)? axisValueFormatter;
  final ValueChanged<DateTime>? onTapPoint;
  final String emptyMessage;

  const TrendLineChart({
    super.key,
    required this.dates,
    required this.series,
    required this.axisLabelBuilder,
    required this.tooltipDateBuilder,
    required this.valueFormatter,
    this.axisValueFormatter,
    this.onTapPoint,
    this.emptyMessage = 'Not enough data yet.',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dates.length < 2 || series.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(emptyMessage, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    final axisFormatter = axisValueFormatter ?? valueFormatter;
    final allValues = [for (final s in series) ...s.values];
    final maxVal = allValues.fold<double>(0, (a, b) => a > b ? a : b);
    final minVal = allValues.fold<double>(0, (a, b) => a < b ? a : b);
    final maxY = maxVal == 0 ? 1.0 : maxVal * 1.15;
    final minY = minVal >= 0 ? 0.0 : minVal * 1.15;
    final yInterval = (maxY - minY) <= 0 ? 1.0 : (maxY - minY) / 4;

    const maxLabels = 6;
    final labelInterval = (dates.length / maxLabels).ceil().clamp(1, dates.length);

    void handleTap(FlTouchEvent event, LineTouchResponse? response) {
      if (event is! FlTapUpEvent) return;
      final spots = response?.lineBarSpots;
      if (spots == null || spots.isEmpty) return;
      final index = spots.first.spotIndex;
      if (index < 0 || index >= dates.length) return;
      onTapPoint?.call(dates[index]);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (series.length > 1) ...[
              Row(
                children: [
                  for (var i = 0; i < series.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    _LegendDot(color: series[i].color, label: series[i].label),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  lineTouchData: LineTouchData(
                    touchCallback: handleTap,
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBorderRadius: BorderRadius.circular(8),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      getTooltipColor: (_) => scheme.onSurface,
                      getTooltipItems: (touchedSpots) {
                        if (touchedSpots.isEmpty) return [];
                        final idx = touchedSpots.first.spotIndex;
                        if (idx < 0 || idx >= dates.length) {
                          return [for (final _ in touchedSpots) null];
                        }
                        return [
                          for (var i = 0; i < touchedSpots.length; i++)
                            LineTooltipItem(
                              i == 0 ? '${tooltipDateBuilder(dates[idx])}\n' : '',
                              TextStyle(
                                color: scheme.surface,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${series[touchedSpots[i].barIndex].label} ${valueFormatter(touchedSpots[i].y)}',
                                  style: TextStyle(
                                    color: series[touchedSpots[i].barIndex].color,
                                    fontSize: 11,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                        ];
                      },
                    ),
                  ),
                  lineBarsData: [
                    for (final s in series)
                      LineChartBarData(
                        spots: [for (var i = 0; i < dates.length; i++) FlSpot(i.toDouble(), s.values[i])],
                        isCurved: false,
                        color: s.color,
                        barWidth: 2.5,
                        dotData: FlDotData(show: dates.length <= 20),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          if (value >= maxY) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              axisFormatter(value),
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) => const SizedBox.shrink(),
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= dates.length) return const SizedBox.shrink();
                          final isLast = idx == dates.length - 1;
                          if (idx % labelInterval != 0 && !isLast) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              axisLabelBuilder(dates[idx]),
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant.withOpacity(0.5), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
