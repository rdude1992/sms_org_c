import '../models/transaction.dart';

class MonthlyTotal {
  final DateTime month; // normalised to the 1st of the month
  final double credit;
  final double debit;
  MonthlyTotal(this.month, this.credit, this.debit);
}

class InstrumentSummary {
  final InstrumentType type;
  final String? ref; // e.g. last-4 digits, or issuer name for grouping
  final String? issuer;
  double totalCredit = 0;
  double totalDebit = 0;
  int count = 0;

  InstrumentSummary({required this.type, this.ref, this.issuer});

  String get displayName {
    final issuerPart = issuer ?? _instrumentLabel(type);
    if (ref != null) return '$issuerPart •• $ref';
    return issuerPart;
  }

  static String _instrumentLabel(InstrumentType t) {
    switch (t) {
      case InstrumentType.creditCard:
        return 'Credit Card';
      case InstrumentType.debitCard:
        return 'Debit Card';
      case InstrumentType.bankAccount:
        return 'Bank Account';
      case InstrumentType.upi:
        return 'UPI';
      case InstrumentType.unknown:
        return 'Other';
    }
  }
}

class InsightsSummary {
  final double totalCredit;
  final double totalDebit;
  final int transactionCount;
  final List<InstrumentSummary> byInstrument;
  final List<MonthlyTotal> monthly;
  final double totalInvested;
  final double totalRedeemed;
  final int investmentEventCount;

  InsightsSummary({
    required this.totalCredit,
    required this.totalDebit,
    required this.transactionCount,
    required this.byInstrument,
    required this.monthly,
    required this.totalInvested,
    required this.totalRedeemed,
    required this.investmentEventCount,
  });

  double get netFlow => totalCredit - totalDebit;
}

class InsightsService {
  InsightsSummary build({
    required List<Transaction> transactions,
    required List<InvestmentEvent> investments,
    DateTime? from,
    DateTime? to,
  }) {
    final filtered = transactions.where((t) {
      if (from != null && t.date.isBefore(from)) return false;
      if (to != null && t.date.isAfter(to)) return false;
      return true;
    }).toList();

    double totalCredit = 0;
    double totalDebit = 0;
    final Map<String, InstrumentSummary> instrumentMap = {};
    final Map<String, MonthlyTotal> monthlyMap = {};

    for (final t in filtered) {
      if (t.direction == TxnDirection.credit) {
        totalCredit += t.amount;
      } else if (t.direction == TxnDirection.debit) {
        totalDebit += t.amount;
      }

      final key = '${t.instrument.name}|${t.issuer ?? ''}|${t.instrumentRef ?? ''}';
      final summary = instrumentMap.putIfAbsent(
        key,
        () => InstrumentSummary(type: t.instrument, ref: t.instrumentRef, issuer: t.issuer),
      );
      if (t.direction == TxnDirection.credit) {
        summary.totalCredit += t.amount;
      } else if (t.direction == TxnDirection.debit) {
        summary.totalDebit += t.amount;
      }
      summary.count += 1;

      final monthKey = DateTime(t.date.year, t.date.month);
      final existing = monthlyMap[monthKey.toIso8601String()];
      final newCredit = (existing?.credit ?? 0) + (t.direction == TxnDirection.credit ? t.amount : 0);
      final newDebit = (existing?.debit ?? 0) + (t.direction == TxnDirection.debit ? t.amount : 0);
      monthlyMap[monthKey.toIso8601String()] = MonthlyTotal(monthKey, newCredit, newDebit);
    }

    final monthlyList = monthlyMap.values.toList()..sort((a, b) => a.month.compareTo(b.month));
    final instrumentList = instrumentMap.values.toList()
      ..sort((a, b) => (b.totalCredit + b.totalDebit).compareTo(a.totalCredit + a.totalDebit));

    double invested = 0;
    double redeemed = 0;
    for (final inv in investments) {
      if (from != null && inv.date.isBefore(from)) continue;
      if (to != null && inv.date.isAfter(to)) continue;
      if (inv.kind == InvestmentKind.mutualFundRedemption) {
        redeemed += inv.amount;
      } else {
        invested += inv.amount;
      }
    }

    return InsightsSummary(
      totalCredit: totalCredit,
      totalDebit: totalDebit,
      transactionCount: filtered.length,
      byInstrument: instrumentList,
      monthly: monthlyList,
      totalInvested: invested,
      totalRedeemed: redeemed,
      investmentEventCount: investments.length,
    );
  }
}
