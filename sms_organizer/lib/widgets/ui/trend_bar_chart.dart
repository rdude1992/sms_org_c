import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/insights_service.dart' show TrendGranularity;
import '../../utils/formatters.dart';

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

  /// Short-year form for the x-axis tick text itself — day/week are already
  /// compact ("15", "15 Aug") and unaffected, but month's "MMM yyyy" (e.g.
  /// "Aug 2025") was wide enough to push the first/last tick's label past
  /// the chart's own edge on a range spanning several years ("All time").
  /// "MMM yy" keeps every tick well inside the reserved anchor width below.
  String _axisLabel(DateTime date) {
    switch (granularity) {
      case TrendGranularity.day:
        return Formatters.dayOnly(date);
      case TrendGranularity.week:
        return Formatters.dayMonth(date);
      case TrendGranularity.month:
        return Formatters.monthYearShort(date);
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

    // However many buckets are in range, only label a handful of them —
    // cramming a label under every single bar is what made this unreadable
    // once a range started putting up to 31 daily bars on screen.
    const maxLabels = 6;
    final labelInterval = (dates.length / maxLabels).ceil().clamp(1, dates.length);

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
              child: BarChart(
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
                        reservedSize: 46,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) {
                          // The top gridline sits at maxY (== maxVal * 1.2,
                          // an intentional headroom margin — see maxY above)
                          // rather than on a "nice" interval boundary, so
                          // its own auto-generated title would show an
                          // oddly precise value floating above the last
                          // real interval tick; fl_chart already omits a
                          // title exactly at maxY by default, but skip it
                          // explicitly too in case rounding ever lands one
                          // on the other side of that check.
                          if (value >= maxY) return const SizedBox.shrink();
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
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

                          final text = Text(
                            _axisLabel(dates[idx]),
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                          );
                          // fl_chart centers this widget directly on top of
                          // its tick. That's fine for an interior label, but
                          // the first/last tick sits right at the plot's own
                          // edge, so a centered multi-character label (e.g.
                          // "May 2019") spills half its width past the
                          // chart's bounds and gets clipped by the Card's
                          // clipBehavior. Reserve extra width to one side
                          // and anchor the text to the inward edge of that
                          // instead, so it grows inward from the tick
                          // rather than off the edge.
                          final isFirst = idx == 0;
                          if (!isFirst && !isLast) {
                            return Padding(padding: const EdgeInsets.only(top: 6), child: text);
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: SizedBox(
                              width: 64,
                              child: Align(
                                alignment: isFirst ? Alignment.centerLeft : Alignment.centerRight,
                                child: text,
                              ),
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
