import 'package:flutter/material.dart';

/// Measures [text]'s rendered width under [style] — used to size a trend
/// chart's axis reserved space to the actual label content instead of a
/// single fixed guess: a compact "₹4.9K" needs far less room than a
/// precise "₹1,234.56", a "day" granularity's "15" needs far less than a
/// "month" granularity's "Aug 25", and neither should be either clipped
/// (guess too small) or wastefully spaced (guess too big) relative to the
/// other. Shared by TrendBarChart and TrendLineChart.
double measureTextWidth(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
