import 'dart:math' as math;

/// Annualised internal rate of return for irregular cash flows (what
/// spreadsheets call XIRR): the rate r at which
/// sum(amount_i / (1 + r)^(days_i / 365)) == 0.
///
/// Money paid in is negative, money received (redemptions, and today's
/// value as the final flow) is positive. Returns null when it's undefined:
/// fewer than two flows, all flows the same sign, or no convergence.
///
/// Newton's method from a 10% guess, falling back to bisection on
/// [-0.9999, 100] (−99.99% to +10,000% a year) when Newton diverges, which
/// it can for short histories or extreme returns.
double? xirr(List<(DateTime, double)> flows) {
  if (flows.length < 2) return null;
  final hasNeg = flows.any((f) => f.$2 < 0);
  final hasPos = flows.any((f) => f.$2 > 0);
  if (!hasNeg || !hasPos) return null;

  final t0 = flows.map((f) => f.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  final years = [for (final f in flows) f.$1.difference(t0).inMinutes / (365 * 24 * 60)];
  final amounts = [for (final f in flows) f.$2];

  double npv(double r) {
    var sum = 0.0;
    for (var i = 0; i < amounts.length; i++) {
      sum += amounts[i] / math.pow(1 + r, years[i]);
    }
    return sum;
  }

  double dNpv(double r) {
    var sum = 0.0;
    for (var i = 0; i < amounts.length; i++) {
      sum -= years[i] * amounts[i] / math.pow(1 + r, years[i] + 1);
    }
    return sum;
  }

  var r = 0.1;
  for (var i = 0; i < 50; i++) {
    final f = npv(r);
    final d = dNpv(r);
    if (d == 0 || f.isNaN) break;
    final next = r - f / d;
    if (next.isNaN || next <= -1) break;
    if ((next - r).abs() < 1e-9) return next;
    r = next;
  }

  // Bisection fallback.
  var lo = -0.9999, hi = 100.0;
  var fLo = npv(lo), fHi = npv(hi);
  if (fLo.isNaN || fHi.isNaN || fLo.sign == fHi.sign) return null;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    final fMid = npv(mid);
    if (fMid.abs() < 1e-7 || (hi - lo) < 1e-10) return mid;
    if (fMid.sign == fLo.sign) {
      lo = mid;
      fLo = fMid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// "12.4%" / "−3.1%" for a rate from [xirr] (0.124 → "12.4%").
String formatXirr(double rate) {
  final pct = rate * 100;
  final text = pct.abs() >= 100 ? pct.abs().toStringAsFixed(0) : pct.abs().toStringAsFixed(1);
  return '${pct < 0 ? '−' : ''}$text%';
}
