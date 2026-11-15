import '../models/transaction.dart';

/// One SIP often produces two SMS: one from the fund house (AMC) and one
/// from its registrar (CAMS / KFintech). Both parse into an
/// [InvestmentEvent], so without this every such installment is counted
/// twice: double the "Invested" total, double the units, and twice the SIP
/// installment count.
///
/// Two events are treated as the same real transaction when:
/// - both are buys (SIP/purchase) or both are redemptions,
/// - the amounts are within ₹1,
/// - the dates are within [window], and
/// - they're plausibly the same fund: the folio matches when both give one,
///   otherwise the scheme names share most of their significant words,
///   otherwise (too little information) the provider key matches.
///
/// That last rule matters: two genuine same-amount SIPs into *different*
/// funds on the same day are common (many people set every SIP for the 5th).
///
/// Of each pair, the event carrying more data (units, NAV, a recognised
/// AMC) is kept; the other's smsId is returned. Valuation statements are
/// never touched.
Set<int> findDuplicateInvestmentIds(
  List<InvestmentEvent> events, {
  Duration window = const Duration(days: 2),
}) {
  final candidates = events.where((e) => !e.kind.isValuationOnly).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final duplicates = <int>{};
  for (var i = 0; i < candidates.length; i++) {
    final a = candidates[i];
    if (duplicates.contains(a.smsId)) continue;
    for (var j = i + 1; j < candidates.length; j++) {
      final b = candidates[j];
      if (b.date.difference(a.date) > window) break;
      if (duplicates.contains(b.smsId)) continue;
      if (a.kind.isRedemption != b.kind.isRedemption) continue;
      if ((a.amount - b.amount).abs() > 1) continue;
      if (!_sameFund(a, b)) continue;
      final dropA = _richness(a) < _richness(b) || (_richness(a) == _richness(b) && a.smsId > b.smsId);
      duplicates.add(dropA ? a.smsId : b.smsId);
      if (dropA) break; // `a` is gone; stop pairing it.
    }
  }
  return duplicates;
}

/// [events] minus the duplicates [findDuplicateInvestmentIds] finds.
List<InvestmentEvent> dedupeInvestments(List<InvestmentEvent> events) {
  final dup = findDuplicateInvestmentIds(events);
  if (dup.isEmpty) return events;
  return [for (final e in events) if (!dup.contains(e.smsId)) e];
}

bool _sameFund(InvestmentEvent a, InvestmentEvent b) {
  final fa = _digitsOrText(a.folioOrAccount);
  final fb = _digitsOrText(b.folioOrAccount);
  if (fa.isNotEmpty && fb.isNotEmpty) {
    // Registrars often mask the folio ("XXXX1234"); compare the visible tail.
    return fa.endsWith(fb) || fb.endsWith(fa) || _tail(fa) == _tail(fb);
  }
  final wa = _schemeWords(a.fundOrScheme);
  final wb = _schemeWords(b.fundOrScheme);
  if (wa.isNotEmpty && wb.isNotEmpty) {
    final overlap = wa.intersection(wb).length;
    final smaller = wa.length < wb.length ? wa.length : wb.length;
    return overlap / smaller >= 0.6;
  }
  return a.providerGroupKey == b.providerGroupKey;
}

String _digitsOrText(String? s) {
  final t = (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 4 ? digits : t;
}

String _tail(String s) => s.length <= 4 ? s : s.substring(s.length - 4);

const _schemeStopWords = {
  'fund', 'plan', 'growth', 'direct', 'regular', 'option', 'scheme', 'the', 'of', 'mf',
  'mutual', 'idcw', 'dividend', 'g', 'dir', 'reg', 'gr',
};

Set<String> _schemeWords(String? s) => (s ?? '')
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.isNotEmpty && !_schemeStopWords.contains(w))
    .toSet();

int _richness(InvestmentEvent e) =>
    ((e.units != null || e.unitsBalance != null) ? 2 : 0) + (e.nav != null ? 1 : 0) + (e.amc != null ? 1 : 0);
