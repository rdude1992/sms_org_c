import '../models/transaction.dart';

class MonthlyTotal {
  final DateTime month; // normalised to the 1st of the month
  final double credit;
  final double debit;
  MonthlyTotal(this.month, this.credit, this.debit);
}

class InstrumentSummary {
  final InstrumentType type;
  final EntityType entityType;
  final String? ref; // e.g. "XX1234", or "Pluxee Card" for numberless cards
  final String? issuer;
  final String? walletType; // e.g. "Fuel Wallet", "HDFC FASTag"
  double totalCredit = 0;
  double totalDebit = 0;
  int count = 0;

  InstrumentSummary({
    required this.type,
    this.entityType = EntityType.unknown,
    this.ref,
    this.issuer,
    this.walletType,
  });

  String get displayName {
    // A specific wallet name ("Fuel Wallet", "HDFC FASTag") is more useful
    // than a generic instrument label, so prefer it when we have one.
    if (walletType != null) return walletType!;

    final issuerPart = issuer ?? _instrumentLabel(type);
    if (ref != null) return '$issuerPart ${_formatRef(ref!)}';
    return issuerPart;
  }

  /// "XX1234" -> "•• 1234"; anything else (e.g. "Pluxee Card") passes
  /// through as-is rather than getting a nonsensical "•• Pluxee Card".
  static String _formatRef(String ref) {
    if (RegExp(r'^XX\d+$').hasMatch(ref)) return '•• ${ref.substring(2)}';
    return '- $ref';
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

      final key = t.walletType != null
          ? 'wallet|${t.walletType}'
          : '${t.instrument.name}|${t.issuer ?? ''}|${t.instrumentRef ?? ''}';
      final summary = instrumentMap.putIfAbsent(
        key,
        () => InstrumentSummary(
          type: t.instrument,
          entityType: t.entityType,
          ref: t.instrumentRef,
          issuer: t.issuer,
          walletType: t.walletType,
        ),
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
