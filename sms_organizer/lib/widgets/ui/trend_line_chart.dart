import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'chart_label_sizing.dart';

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

  static const _axisLabelStyle = TextStyle(fontSize: 10);
  static const _rightReservedSize = 28.0;

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

    // Widest y-axis tick label actually reachable at this interval — sizes
    // the reserved left column to the real content (a precise "₹1,234.56"
    // needs much more room than a compact "₹4.9K") instead of a single
    // fixed guess that clips one and wastes space for the other.
    final yTickWidth = [for (var v = minY; v <= maxY + 0.001; v += yInterval) axisFormatter(v)]
        .fold<double>(0, (w, label) => math.max(w, measureTextWidth(label, _axisLabelStyle)));
    final leftReservedSize = (yTickWidth + 12).clamp(32.0, 84.0);

    // Widest x-axis label across every bucket, used below to figure out how
    // many labels can actually fit side by side without overlapping — a
    // "month" granularity's "Aug 25" needs more horizontal room per label
    // than a "day" granularity's "15", so the same fixed label count would
    // either cram the wide ones or under-use the room short ones leave free.
    final xLabelWidth =
        dates.fold<double>(0, (w, d) => math.max(w, measureTextWidth(axisLabelBuilder(d), _axisLabelStyle)));
    // Bottom axis needs extra vertical room when a caller's axisLabelBuilder
    // embeds a newline to stack a tick onto two lines (e.g. AmcDetailScreen's
    // month-granularity "Aug"/"25" split — see Formatters.monthOnly) —
    // Text renders that as two lines automatically, this just reserves room.
    final hasMultilineXLabels = dates.any((d) => axisLabelBuilder(d).contains('\n'));

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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Available width for x-axis labels, once the (now
                  // dynamically-sized) left/right axis columns are spoken
                  // for — the actual budget label-thinning has to fit into,
                  // rather than a plot-width guess baked in beforehand.
                  final plotWidth =
                      (constraints.maxWidth - leftReservedSize - _rightReservedSize).clamp(1.0, double.infinity);
                  final labelSlot = xLabelWidth + 14;
                  final maxLabels = (plotWidth / labelSlot).floor().clamp(2, dates.length);
                  final labelInterval = (dates.length / maxLabels).ceil().clamp(1, dates.length);

                  return LineChart(
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
                            reservedSize: leftReservedSize,
                            interval: yInterval,
                            getTitlesWidget: (value, meta) {
                              if (value >= maxY) return const SizedBox.shrink();
                              // fl_chart's own tick-value math (minY + N *
                              // yInterval) can land a hair off an intended
                              // step due to floating point — passed through
                              // unfiltered, that draws an extra label almost
                              // exactly on top of a real one (most visible
                              // right at the minY/"₹0" row). Only render a
                              // title for values that land on an actual
                              // step from minY, so a near-duplicate never
                              // gets drawn.
                              final stepsFromMin = (value - minY) / yInterval;
                              if ((stepsFromMin - stepsFromMin.roundToDouble()).abs() > 0.02) {
                                return const SizedBox.shrink();
                              }
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
                            reservedSize: _rightReservedSize,
                            getTitlesWidget: (value, meta) => const SizedBox.shrink(),
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: hasMultilineXLabels ? 36 : 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= dates.length) return const SizedBox.shrink();
                              final isLast = idx == dates.length - 1;
                              if (idx % labelInterval != 0 && !isLast) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  axisLabelBuilder(dates[idx]),
                                  textAlign: TextAlign.center,
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
                  );
                },
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
