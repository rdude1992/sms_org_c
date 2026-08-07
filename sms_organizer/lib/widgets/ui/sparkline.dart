import 'package:flutter/material.dart';

/// A minimal inline trend line — no axes, no grid, just a stroked path
/// through normalised points with a soft fill underneath and a dot marking
/// the latest value. Deliberately hand-painted rather than built on
/// fl_chart: a full chart widget per list row (touch handling, borders,
/// grid) is a lot of overhead for something this small.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double width;
  final double height;

  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 56,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(width: width, height: height);
    }
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparklinePainter(values: values, color: color)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final stepX = size.width / (values.length - 1);

    double yFor(double value) => size.height - ((value - minV) / range) * size.height;

    final path = Path()..moveTo(0, yFor(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(i * stepX, yFor(values[i]));
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withOpacity(0.12));

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      Offset(size.width, yFor(values.last)),
      2.2,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
