import 'package:flutter_test/flutter_test.dart';
import 'package:sms_organizer/models/transaction.dart';
import 'package:sms_organizer/services/budget_service.dart';
import 'package:sms_organizer/services/holdings_service.dart';
import 'package:sms_organizer/utils/xirr.dart';

InvestmentEvent _inv(int id, double amount, DateTime date,
        {InvestmentKind kind = InvestmentKind.mutualFundSip, String? amc, String? fund, double? units, double? nav}) =>
    InvestmentEvent(
      smsId: id,
      date: date,
      amount: amount,
      kind: kind,
      rawBody: 'inv $id',
      amc: amc,
      fundOrScheme: fund,
      units: units,
      nav: nav,
    );

void main() {
  group('xirr', () {
    test('10% over exactly one year', () {
      final r = xirr([(DateTime(2025, 1, 1), -10000), (DateTime(2026, 1, 1), 11000)]);
      expect(r, closeTo(0.10, 1e-6));
    });

    test('irregular SIP flows (cross-checked independently: 9.229%)', () {
      final r = xirr([
        (DateTime(2025, 1, 1), -1000),
        (DateTime(2025, 2, 1), -1000),
        (DateTime(2025, 3, 1), -1000),
        (DateTime(2026, 3, 1), 3300),
      ]);
      expect(r! * 100, closeTo(9.229, 0.01));
    });

    test('a loss comes out negative', () {
      final r = xirr([(DateTime(2025, 1, 1), -10000), (DateTime(2026, 1, 1), 9000)]);
      expect(r, closeTo(-0.10, 1e-6));
    });

    test('undefined when every flow has the same sign', () {
      expect(xirr([(DateTime(2025, 1, 1), -1000), (DateTime(2025, 6, 1), -1000)]), isNull);
    });

    test('formatXirr', () {
      expect(formatXirr(0.1243), '12.4%');
      expect(formatXirr(-0.031), '−3.1%');
    });
  });

  test('holding return is hidden with under 30 days of history', () {
    final now = DateTime(2026, 11, 15);
    final h = computeFundHoldings([
      _inv(1, 1000, now.subtract(const Duration(days: 10)), fund: 'Axis Bluechip', units: 20, nav: 50),
    ]).single;
    expect(h.xirrAsOf(now), isNull);
  });

  group('budgets', () {
    BudgetStatus status(double spent) =>
        BudgetStatus(category: SpendCategory.foodDining, limit: 10000, spent: spent);

    test('alerts at 80% once, then at 100%', () {
      expect(thresholdToAlert(status(7900), {}), isNull);
      expect(thresholdToAlert(status(8000), {}), 80);
      expect(thresholdToAlert(status(9500), {80}), isNull);
      expect(thresholdToAlert(status(10000), {80}), 100);
    });

    test('jumping straight past 100% sends only the 100% alert', () {
      expect(thresholdToAlert(status(12000), {}), 100);
    });

    test('non-spend categories and income cannot be budgeted', () {
      expect(budgetableCategories, isNot(contains(SpendCategory.creditCardPayment)));
      expect(budgetableCategories, isNot(contains(SpendCategory.transfer)));
      expect(budgetableCategories, isNot(contains(SpendCategory.investment)));
      expect(budgetableCategories, isNot(contains(SpendCategory.income)));
      expect(budgetableCategories, contains(SpendCategory.foodDining));
    });
  });

  group('assetClassOf', () {
    final d = DateTime(2026, 1, 1);
    AssetClass classOf(InvestmentEvent e) => assetClassOf(computeFundHoldings([e]).single);

    test('NPS by provider name, even though parsed as a purchase', () {
      expect(classOf(_inv(1, 5000, d, kind: InvestmentKind.mutualFundPurchase, amc: 'NPS Trust')), AssetClass.nps);
    });
    test('stocks by kind', () {
      expect(classOf(_inv(1, 5000, d, kind: InvestmentKind.stockTrade, amc: 'Zerodha')), AssetClass.stocks);
    });
    test('mutual fund SIP', () {
      expect(classOf(_inv(1, 5000, d, amc: 'Axis Mutual Fund')), AssetClass.mutualFunds);
    });
  });
}
