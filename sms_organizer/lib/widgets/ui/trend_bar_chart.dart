import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/insights_service.dart' show TrendGranularity;
import '../../utils/formatters.dart';
import 'chart_label_sizing.dart';

/// Stacked bar chart of two values (e.g. credited/debited, invested/
/// redeemed) per date bucket, with an "Avg X / Y per <bucket>" caption and
/// a tap-to-drilldown callback. Bucket labels and the caption's unit both
/// adapt to [granularity] (day/week/month) — shared by the Insights trend
/// chart and the Investments "by AMC" trend chart, which both need this
/// exact chart just fed from different data.
class TrendBarChart extends StatelessWidget {
  final List<DateTime> dates;
  final List<double> primaryValues;
  final List<double> secondaryValues;
  final TrendGranularity granularity;
  final String primaryLabel;
  final String secondaryLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final ValueChanged<DateTime> onTapBucket;

  const TrendBarChart({
    super.key,
    required this.dates,
    required this.primaryValues,
    required this.secondaryValues,
    required this.granularity,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onTapBucket,
  });

  /// Full-year form — used for the tooltip header, which has room for it.
  String _bucketLabel(DateTime date) {
    switch (granularity) {
      case TrendGranularity.day:
        return Formatters.dayOnly(date);
      case TrendGranularity.week:
        return Formatters.dayMonth(date);
      case TrendGranularity.month:
        return Formatters.monthYear(date);
    }
  }

  /// The x-axis tick text itself — day/week are already compact ("15", "15
  /// Aug") and just one line, but month's "MMM yyyy" (e.g. "Aug 2025") was
  /// wide enough that adjacent ticks' labels ran into each other on a range
  /// spanning several years ("All time"). Embeds a newline to stack month
  /// above a short year on two lines instead — Text renders it as two
  /// lines automatically, and [measureTextWidth] (used below to size the
  /// reserved axis width) already reports a multi-line string's widest
  /// line, so this needs no special-casing beyond the extra vertical room
  /// [hasMultilineXLabels] reserves in bottomTitles.
  String _axisLabel(DateTime date) {
    switch (granularity) {
      case TrendGranularity.day:
        return Formatters.dayOnly(date);
      case TrendGranularity.week:
        return Formatters.dayMonth(date);
      case TrendGranularity.month:
        return '${Formatters.monthOnly(date)}\n${Formatters.yearOnlyShort(date)}';
    }
  }

  String get _perBucketLabel {
    switch (granularity) {
      case TrendGranularity.day:
        return 'day';
      case TrendGranularity.week:
        return 'week';
      case TrendGranularity.month:
        return 'month';
    }
  }

  static const _axisLabelStyle = TextStyle(fontSize: 10);
  static const _rightReservedSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dates.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('Not enough data yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    final maxVal = [
      for (var i = 0; i < dates.length; i++) primaryValues[i] + secondaryValues[i],
    ].fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxVal == 0 ? 1.0 : maxVal * 1.2;
    final avgPrimary = primaryValues.reduce((a, b) => a + b) / primaryValues.length;
    final avgSecondary = secondaryValues.reduce((a, b) => a + b) / secondaryValues.length;

    // Widest y-axis tick label actually reachable at this interval — a
    // stretch of large-amount buckets (₹ lakhs/crores) needs a visibly
    // wider reserved column than a stretch of small ones, instead of a
    // single fixed guess that clips one and wastes space for the other.
    final yTickWidth = [for (var v = 0.0; v <= maxY + 0.001; v += maxY / 4) Formatters.compactCurrency(v)]
        .fold<double>(0, (w, label) => math.max(w, measureTextWidth(label, _axisLabelStyle)));
    final leftReservedSize = (yTickWidth + 12).clamp(32.0, 84.0);

    // Widest x-axis label across every bucket — a "month" granularity's
    // "Aug 25" needs more horizontal room per label than a "day"
    // granularity's "15", so however many labels actually fit without
    // overlapping varies with which granularity is showing, not a single
    // fixed count regardless of period.
    final xLabelWidth =
        dates.fold<double>(0, (w, d) => math.max(w, measureTextWidth(_axisLabel(d), _axisLabelStyle)));
    // Bottom axis needs extra vertical room once labels wrap to two lines
    // (see _axisLabel) — checked once here rather than per-tick since it's
    // the same answer (this chart's granularity) for every tick.
    final hasMultilineXLabels = dates.any((d) => _axisLabel(d).contains('\n'));

    // Narrower, tighter-packed bars once there are enough buckets that
    // full-width bars would overlap (31 daily bars vs. 12 monthly ones).
    final barWidth = dates.length > 20 ? 5.0 : (dates.length > 10 ? 9.0 : 16.0);
    final groupsSpace = dates.length > 20 ? 3.0 : (dates.length > 10 ? 6.0 : 14.0);

    void handleTap(FlTouchEvent event, BarTouchResponse? response) {
      if (event is! FlTapUpEvent) return;
      final index = response?.spot?.touchedBarGroupIndex;
      if (index == null || index < 0 || index >= dates.length) return;
      onTapBucket(dates[index]);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _LegendDot(color: primaryColor, label: primaryLabel),
                const SizedBox(width: 16),
                _LegendDot(color: secondaryColor, label: secondaryLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Avg ${Formatters.currency(avgPrimary)} ${primaryLabel.toLowerCase()} · '
              '${Formatters.currency(avgSecondary)} ${secondaryLabel.toLowerCase()} / $_perBucketLabel',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Available width for x-axis labels, once the (now
                  // dynamically-sized) left/right axis columns are spoken
                  // for — the actual budget label-thinning has to fit
                  // into, rather than a plot-width guess baked in
                  // beforehand.
                  final plotWidth = (constraints.maxWidth - leftReservedSize - _rightReservedSize)
                      .clamp(1.0, double.infinity);
                  final labelSlot = xLabelWidth + 14;
                  final maxLabels = (plotWidth / labelSlot).floor().clamp(2, dates.length);
                  final labelInterval = (dates.length / maxLabels).ceil().clamp(1, dates.length);

                  return BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: maxY,
                      alignment: BarChartAlignment.spaceEvenly,
                      groupsSpace: groupsSpace,
                      barTouchData: BarTouchData(
                        touchCallback: handleTap,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBorderRadius: BorderRadius.circular(8),
                          tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          getTooltipColor: (_) => scheme.onSurface,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (groupIndex < 0 || groupIndex >= dates.length) return null;
                            return BarTooltipItem(
                              '${_bucketLabel(dates[groupIndex])}\n',
                              TextStyle(
                                color: scheme.surface,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                              children: [
                                TextSpan(
                                  text: '$primaryLabel ${Formatters.currency(primaryValues[groupIndex])}\n',
                                  style: TextStyle(color: primaryColor, fontSize: 11, fontFamily: 'Inter'),
                                ),
                                TextSpan(
                                  text: '$secondaryLabel ${Formatters.currency(secondaryValues[groupIndex])}',
                                  style: TextStyle(color: secondaryColor, fontSize: 11, fontFamily: 'Inter'),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < dates.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: primaryValues[i] + secondaryValues[i],
                                width: barWidth,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                rodStackItems: [
                                  BarChartRodStackItem(0, primaryValues[i], primaryColor),
                                  BarChartRodStackItem(
                                    primaryValues[i],
                                    primaryValues[i] + secondaryValues[i],
                                    secondaryColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: leftReservedSize,
                            interval: maxY / 4,
                            getTitlesWidget: (value, meta) {
                              // The top gridline sits at maxY (== maxVal *
                              // 1.2, an intentional headroom margin — see
                              // maxY above) rather than on a "nice"
                              // interval boundary, so its own
                              // auto-generated title would show an oddly
                              // precise value floating above the last real
                              // interval tick; fl_chart already omits a
                              // title exactly at maxY by default, but skip
                              // it explicitly too in case rounding ever
                              // lands one on the other side of that check.
                              if (value >= maxY) return const SizedBox.shrink();
                              // Same defensive rounding as TrendLineChart's
                              // leftTitles — fl_chart's own tick math (0, N
                              // * maxY/4) can land a hair off an intended
                              // step due to floating point, which otherwise
                              // draws an extra label almost exactly on top
                              // of a real one (most visible right at the
                              // "₹0" row).
                              final stepsFromMin = value / (maxY / 4);
                              if ((stepsFromMin - stepsFromMin.roundToDouble()).abs() > 0.02) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  Formatters.compactCurrency(value),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                ),
                              );
                            },
                          ),
                        ),
                        // fl_chart centers every bottom-title widget
                        // directly on top of its own tick, with no notion
                        // of "this tick is at the plot's edge, give its
                        // label room to overhang." Trying to fix that
                        // per-label (anchoring the first/last label's text
                        // to whichever side of a wide reserved box stays
                        // inward) kept failing in practice — half the
                        // label's reserved box still extends past the
                        // plot's actual drawing area regardless of how the
                        // text inside it is aligned, and *that* half is
                        // what the Card's clipBehavior was cutting off.
                        // Reserving real margin on both sides of the plot
                        // instead — leftTitles already does this
                        // incidentally (leftReservedSize, for the y-axis
                        // labels); rightTitles below does it on purpose,
                        // with nothing to actually draw there — sidesteps
                        // the problem entirely: every tick, including the
                        // first/last, now sits far enough from the Card's
                        // edge that a centered label never reaches it, so
                        // no per-label special-casing is needed at all.
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
                                  _axisLabel(dates[idx]),
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
                        horizontalInterval: maxY / 4,
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
