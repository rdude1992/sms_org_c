import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sms_organizer/models/transaction.dart';
import 'package:sms_organizer/services/holdings_service.dart';
import 'package:sms_organizer/services/insights_service.dart';
import 'package:sms_organizer/services/investment_dedup_service.dart';
import 'package:sms_organizer/widgets/ui/trend_bar_chart.dart';

Transaction _txn(int id, double amount, TxnDirection dir, DateTime date, {SpendCategory? category}) =>
    Transaction(
      smsId: id,
      date: date,
      amount: amount,
      direction: dir,
      instrument: InstrumentType.bankAccount,
      instrumentRef: 'XX$id',
      rawBody: 'test $id',
      spendCategory: category,
    );

InvestmentEvent _inv(
  int id,
  double amount,
  DateTime date, {
  InvestmentKind kind = InvestmentKind.mutualFundSip,
  String? fund,
  String? folio,
  String? amc,
  double? units,
  double? unitsBalance,
  double? nav,
}) =>
    InvestmentEvent(
      smsId: id,
      date: date,
      amount: amount,
      kind: kind,
      rawBody: 'inv $id',
      fundOrScheme: fund,
      folioOrAccount: folio,
      amc: amc,
      units: units,
      unitsBalance: unitsBalance,
      nav: nav,
    );

void main() {
  group('bucketStartsBetween', () {
    test('day buckets are every calendar midnight across a month end', () {
      final days = bucketStartsBetween(DateTime(2026, 10, 29), DateTime(2026, 11, 2), TrendGranularity.day);
      expect(days, [
        DateTime(2026, 10, 29),
        DateTime(2026, 10, 30),
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ]);
      expect(days.every((d) => d.hour == 0 && d.minute == 0), isTrue);
    });

    test('week buckets start on Mondays at midnight', () {
      final weeks = bucketStartsBetween(DateTime(2026, 9, 1), DateTime(2026, 11, 15), TrendGranularity.week);
      expect(weeks.first, DateTime(2026, 8, 31));
      expect(weeks.every((d) => d.weekday == DateTime.monday && d.hour == 0), isTrue);
    });
  });

  test('totalSpend leaves out card bills, transfers and investment debits', () {
    final d = DateTime(2026, 11, 3);
    final summary = InsightsService().build(
      transactions: [
        _txn(1, 500, TxnDirection.debit, d, category: SpendCategory.foodDining),
        _txn(2, 20000, TxnDirection.debit, d.add(const Duration(days: 1)), category: SpendCategory.creditCardPayment),
        _txn(3, 7000, TxnDirection.debit, d.add(const Duration(days: 2)), category: SpendCategory.transfer),
        _txn(4, 3000, TxnDirection.debit, d.add(const Duration(days: 3)), category: SpendCategory.investment),
        _txn(5, 250, TxnDirection.debit, d.add(const Duration(days: 4))), // uncategorised still counts
        _txn(6, 90000, TxnDirection.credit, d.add(const Duration(days: 5)), category: SpendCategory.income),
      ],
      investments: const [],
    );
    expect(summary.totalDebit, 30750);
    expect(summary.totalSpend, 750);
    expect(summary.totalCredit, 90000);
  });

  group('findDuplicateInvestmentIds', () {
    final day = DateTime(2026, 10, 5);

    test('AMC + registrar SMS for one SIP: keeps the richer one', () {
      final amc = _inv(1, 5000, day, fund: 'Axis Bluechip Fund Direct Growth', folio: '91012345', amc: 'Axis MF', units: 98.1, nav: 50.97);
      final cams = _inv(2, 5000, day.add(const Duration(days: 1)), fund: 'Axis Bluechip Fund - Direct Plan - Growth', folio: 'XXXX2345');
      expect(findDuplicateInvestmentIds([amc, cams]), {2});
    });

    test('same amount, same day, different funds: both kept', () {
      final a = _inv(1, 1000, day, fund: 'Parag Parikh Flexi Cap', amc: 'PPFAS MF');
      final b = _inv(2, 1000, day, fund: 'HDFC Index Nifty 50', amc: 'HDFC MF');
      expect(findDuplicateInvestmentIds([a, b]), isEmpty);
    });

    test('monthly SIPs of the same amount are not merged', () {
      final a = _inv(1, 2000, day, fund: 'Axis Bluechip', folio: '91012345');
      final b = _inv(2, 2000, DateTime(2026, 11, 5), fund: 'Axis Bluechip', folio: '91012345');
      expect(findDuplicateInvestmentIds([a, b]), isEmpty);
    });

    test('a buy and a redemption are never merged', () {
      final a = _inv(1, 3000, day, fund: 'Axis Bluechip', folio: '91012345');
      final b = _inv(2, 3000, day, fund: 'Axis Bluechip', folio: '91012345', kind: InvestmentKind.mutualFundRedemption);
      expect(findDuplicateInvestmentIds([a, b]), isEmpty);
    });
  });

  test('a fully redeemed holding is worth 0 and shows the realised gain', () {
    final holding = computeFundHoldings([
      _inv(1, 10000, DateTime(2025, 1, 10), kind: InvestmentKind.mutualFundPurchase, fund: 'Axis Bluechip', folio: '1', units: 200, nav: 50),
      _inv(2, 12000, DateTime(2026, 1, 10), kind: InvestmentKind.mutualFundRedemption, fund: 'Axis Bluechip', folio: '1', units: 200, nav: 60),
    ]).single;
    expect(holding.estimatedValue, 0);
    expect(holding.estimatedGain, 2000);
  });

  testWidgets('trend bar chart renders with a single bucket', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TrendBarChart(
          dates: [DateTime(2026, 11, 1)],
          primaryValues: const [100],
          secondaryValues: const [50],
          granularity: TrendGranularity.day,
          primaryLabel: 'Credited',
          secondaryLabel: 'Debited',
          primaryColor: Colors.green,
          secondaryColor: Colors.red,
          onTapBucket: (_) {},
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(TrendBarChart), findsOneWidget);
  });
}
