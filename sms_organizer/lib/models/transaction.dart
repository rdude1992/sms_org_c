import 'package:flutter/material.dart';

/// `reversal` is new (ported from getTransactionType in the source regex
/// file): covers "reversed"/"declined"/"failed" transactions, which
/// shouldn't count toward either credit or debit totals.
enum TxnDirection { credit, debit, reversal, unknown }

enum InstrumentType { debitCard, creditCard, bankAccount, upi, unknown }

/// Ported from extractEntityType in the source regex file — a coarser
/// classification than [InstrumentType]: is this message from a bank, a
/// wallet provider (Paytm/PhonePe/Pluxee/FASTag/...), an investment
/// platform, or a dedicated card-network service (Visa/Amex/...)?
enum EntityType { bank, wallet, investment, cardService, unknown }

/// What a transaction was actually *for* — Food, Transport, Bills, etc.
/// [Transaction.spendCategory] starts null ("Uncategorised") until tagged —
/// either by the user via SmsProvider.updateTransaction, or by a confident
/// merchant/keyword match from SpendCategoryDetector. The detector is
/// deliberately conservative and never overwrites a value the user chose
/// (see there): "spend category" is a judgment call about a purchase's
/// purpose that varies by transaction even for the same merchant (e.g. a
/// supermarket run can be groceries or household goods), so anything it
/// can't confidently infer from the merchant/body is left for the user
/// rather than guessed.
enum SpendCategory {
  foodDining,
  groceries,
  transport,
  shopping,
  billsUtilities,
  creditCardPayment,
  entertainment,
  health,
  travel,
  housing,
  education,
  investment,
  transfer,
  income,
  other,
}

extension SpendCategoryX on SpendCategory {
  String get label {
    switch (this) {
      case SpendCategory.foodDining:
        return 'Food & Dining';
      case SpendCategory.groceries:
        return 'Groceries';
      case SpendCategory.transport:
        return 'Transport';
      case SpendCategory.shopping:
        return 'Shopping';
      case SpendCategory.billsUtilities:
        return 'Bills & Utilities';
      case SpendCategory.creditCardPayment:
        return 'Credit Card Payment';
      case SpendCategory.entertainment:
        return 'Entertainment';
      case SpendCategory.health:
        return 'Health';
      case SpendCategory.travel:
        return 'Travel';
      case SpendCategory.housing:
        return 'Housing & Rent';
      case SpendCategory.education:
        return 'Education';
      case SpendCategory.investment:
        return 'Investment';
      case SpendCategory.transfer:
        return 'Transfer';
      case SpendCategory.income:
        return 'Income';
      case SpendCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case SpendCategory.foodDining:
        return Icons.restaurant_outlined;
      case SpendCategory.groceries:
        return Icons.local_grocery_store_outlined;
      case SpendCategory.transport:
        return Icons.directions_car_outlined;
      case SpendCategory.shopping:
        return Icons.shopping_bag_outlined;
      case SpendCategory.billsUtilities:
        return Icons.receipt_long_outlined;
      case SpendCategory.creditCardPayment:
        return Icons.credit_card;
      case SpendCategory.entertainment:
        return Icons.movie_outlined;
      case SpendCategory.health:
        return Icons.local_hospital_outlined;
      case SpendCategory.travel:
        return Icons.flight_outlined;
      case SpendCategory.housing:
        return Icons.home_outlined;
      case SpendCategory.education:
        return Icons.school_outlined;
      case SpendCategory.investment:
        return Icons.trending_up;
      case SpendCategory.transfer:
        return Icons.swap_horiz;
      case SpendCategory.income:
        return Icons.payments_outlined;
      case SpendCategory.other:
        return Icons.category_outlined;
    }
  }

  Color get color {
    switch (this) {
      case SpendCategory.foodDining:
        return const Color(0xFFF59E0B);
      case SpendCategory.groceries:
        return const Color(0xFF10B981);
      case SpendCategory.transport:
        return const Color(0xFF3B82F6);
      case SpendCategory.shopping:
        return const Color(0xFFEC4899);
      case SpendCategory.billsUtilities:
        return const Color(0xFFEF4444);
      case SpendCategory.creditCardPayment:
        return const Color(0xFF0F766E);
      case SpendCategory.entertainment:
        return const Color(0xFF8B5CF6);
      case SpendCategory.health:
        return const Color(0xFF06B6D4);
      case SpendCategory.travel:
        return const Color(0xFFC96442);
      case SpendCategory.housing:
        return const Color(0xFF64748B);
      case SpendCategory.education:
        return const Color(0xFF0EA5E9);
      case SpendCategory.investment:
        return const Color(0xFF6366F1);
      case SpendCategory.transfer:
        return const Color(0xFF9CA3AF);
      case SpendCategory.income:
        return const Color(0xFF22C55E);
      case SpendCategory.other:
        return const Color(0xFF6B7280);
    }
  }
}

/// Parses a stored/backed-up [SpendCategory] name back into its enum value —
/// a plain loop (rather than `SpendCategory.values.firstWhere`) because the
/// null case (no category assigned, or an unrecognised name from an older
/// backup) needs to stay null rather than falling back to some default
/// category that wasn't actually chosen.
SpendCategory? parseSpendCategory(String? name) {
  if (name == null) return null;
  for (final c in SpendCategory.values) {
    if (c.name == name) return c;
  }
  return null;
}

/// Collapses an SMS body to its underlying template — strips every digit
/// run (amounts, account/reference numbers, dates, balances) and
/// normalises whitespace/case, so two alerts generated from the same bank
/// template collapse to an identical string even though none of their
/// numbers match. Shared by SmsProvider.findSimilarUnassignedTransactions
/// and [Transaction.categoryReviewGroupKey].
String normalizedSmsTemplate(String body) {
  return body.toLowerCase().replaceAll(RegExp(r'\d+'), '#').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Sentinel default for [Transaction.copyWith]'s nullable-field params, so
/// "not passed" (keep existing value) is distinguishable from "passed
/// null" (clear the field).
const _unset = Object();

class Transaction {
  final int smsId;
  final DateTime date;
  final double amount;
  final TxnDirection direction;
  final InstrumentType instrument;

  /// e.g. last 4 digits of card/account, or the UPI handle if detected.
  /// Falls back to "Pluxee Card" for cards that never surface a number.
  final String? instrumentRef;

  /// Bank / issuer name if detected from the sender ID (e.g. "HDFC", "ICICI")
  /// or, failing that, from a gift-card brand mentioned in the body.
  final String? issuer;

  /// Merchant / payee name if the SMS format included one.
  final String? merchant;

  /// Available/remaining balance if the SMS mentioned it.
  final double? balanceAfter;

  /// Bank / wallet / investment / card-service classification (see
  /// [EntityType]) — coarser than [instrument], useful for grouping wallet
  /// spend separately from card/bank spend in Insights.
  final EntityType entityType;

  /// Specific wallet name if [entityType] is wallet, e.g. "Fuel Wallet",
  /// "HDFC FASTag", "Paytm Wallet".
  final String? walletType;

  /// Due date mentioned in the SMS, if any (e.g. credit card payment
  /// reminders that also confirm a transaction).
  final DateTime? billDueDate;

  /// FASTag-specific: the wallet id/account number for toll transactions.
  final String? fastagWalletId;

  /// FASTag-specific: the vehicle number the toll was charged against.
  final String? vehicleNumber;

  final String rawBody;

  /// True once the user has manually corrected [direction]/[instrument]/
  /// [merchant]/[walletType] via SmsProvider.updateTransaction — see that
  /// method for why TransactionParserService never re-derives and
  /// overwrites this row after that.
  final bool isOverridden;

  /// What this transaction was actually for — null ("Uncategorised") until
  /// tagged, either by the user or by a confident SpendCategoryDetector
  /// merchant/keyword match (see there — never [isOverridden], so it's
  /// always a starting point rather than a claim about user intent).
  final SpendCategory? spendCategory;

  Transaction({
    required this.smsId,
    required this.date,
    required this.amount,
    required this.direction,
    required this.instrument,
    required this.rawBody,
    this.instrumentRef,
    this.issuer,
    this.merchant,
    this.balanceAfter,
    this.entityType = EntityType.unknown,
    this.walletType,
    this.billDueDate,
    this.fastagWalletId,
    this.vehicleNumber,
    this.isOverridden = false,
    this.spendCategory,
  });

  /// Field-level overrides on top of this transaction's existing values —
  /// e.g. the spend-category backfill only ever needs to change one field,
  /// and rebuilding the other dozen unchanged would just be noise at every
  /// call site. `Object?`-sentinel params ([instrumentRef]/[issuer]) let a
  /// caller explicitly clear a field to null (distinct from "leave it
  /// alone") the same way the rest of this codebase's edit flows do.
  Transaction copyWith({
    TxnDirection? direction,
    InstrumentType? instrument,
    Object? instrumentRef = _unset,
    Object? issuer = _unset,
    Object? merchant = _unset,
    Object? walletType = _unset,
    bool? isOverridden,
    Object? spendCategory = _unset,
  }) {
    return Transaction(
      smsId: smsId,
      date: date,
      amount: amount,
      direction: direction ?? this.direction,
      instrument: instrument ?? this.instrument,
      rawBody: rawBody,
      instrumentRef: identical(instrumentRef, _unset) ? this.instrumentRef : instrumentRef as String?,
      issuer: identical(issuer, _unset) ? this.issuer : issuer as String?,
      merchant: identical(merchant, _unset) ? this.merchant : merchant as String?,
      balanceAfter: balanceAfter,
      entityType: entityType,
      walletType: identical(walletType, _unset) ? this.walletType : walletType as String?,
      billDueDate: billDueDate,
      fastagWalletId: fastagWalletId,
      vehicleNumber: vehicleNumber,
      isOverridden: isOverridden ?? this.isOverridden,
      spendCategory:
          identical(spendCategory, _unset) ? this.spendCategory : spendCategory as SpendCategory?,
    );
  }

  /// Groups transactions the same way Insights buckets "by card / account" —
  /// a specific wallet name if there is one, else instrument+issuer+ref.
  /// Shared with [InsightsService] and instrument-drilldown filtering so the
  /// two stay in lockstep.
  ///
  /// A debit card is just the physical instrument tied to its linked
  /// savings account, so a debit-card SMS and a bank-account SMS from the
  /// same issuer that surface the same last-4 [instrumentRef] almost
  /// certainly refer to the same underlying money — group them together
  /// rather than splitting "HDFC debit card ••1234" from "HDFC account
  /// ••1234" into two rows. Only merge when a ref was actually detected;
  /// two ref-less entries can't be confidently linked, so they fall back
  /// to being split by instrument type as before. Credit cards are a
  /// separate credit facility, not a linked account, so they never merge
  /// into this bucket even if a last-4 happens to coincide.
  String get instrumentGroupKey {
    if (walletType != null) return 'wallet|$walletType';
    if ((instrument == InstrumentType.debitCard || instrument == InstrumentType.bankAccount) &&
        instrumentRef != null) {
      return 'account|${issuer ?? ''}|$instrumentRef';
    }
    return '${instrument.name}|${issuer ?? ''}|${instrumentRef ?? ''}';
  }

  /// Groups transactions by merchant/payee for Insights' "By merchant"
  /// view — normalised (trimmed, whitespace-collapsed, lower-cased) so
  /// trivial formatting differences between two SMS from the same merchant
  /// (extra space, different casing) don't split them into separate
  /// groups; [merchant] itself keeps its original casing for display. Null
  /// when no merchant was detected — those transactions (salary credits,
  /// self-transfers, ambiguous SMS formats) are excluded from merchant
  /// grouping rather than lumped into a meaningless "Unknown" bucket.
  String? get merchantGroupKey {
    final trimmed = merchant?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  /// Best available grouping key for "these are probably the same
  /// real-world sender" purposes when there's no [merchantGroupKey] to use
  /// — falls back to [normalizedSmsTemplate], which collapses every digit
  /// run (amounts, account numbers, dates, references — everything that's
  /// supposed to differ message-to-message) so two alerts generated from
  /// the same bank template collapse to an identical string even though
  /// none of their numbers match. Used by UncategorisedReviewScreen to
  /// group merchant-less transactions (bare NEFT/IMPS transfers, generic
  /// bank alerts) that [merchantGroupKey] alone would leave as one
  /// singleton per transaction.
  String get categoryReviewGroupKey => merchantGroupKey ?? 'tmpl:${normalizedSmsTemplate(rawBody)}';

  Map<String, dynamic> toJson() => {
        'smsId': smsId,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'direction': direction.name,
        'instrument': instrument.name,
        'instrumentRef': instrumentRef,
        'issuer': issuer,
        'merchant': merchant,
        'balanceAfter': balanceAfter,
        'entityType': entityType.name,
        'walletType': walletType,
        'billDueDate': billDueDate?.millisecondsSinceEpoch,
        'fastagWalletId': fastagWalletId,
        'vehicleNumber': vehicleNumber,
        'rawBody': rawBody,
        'isOverridden': isOverridden,
        'spendCategory': spendCategory?.name,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        smsId: json['smsId'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
        amount: (json['amount'] as num).toDouble(),
        direction: TxnDirection.values.firstWhere((e) => e.name == json['direction'],
            orElse: () => TxnDirection.unknown),
        instrument: InstrumentType.values.firstWhere((e) => e.name == json['instrument'],
            orElse: () => InstrumentType.unknown),
        rawBody: json['rawBody'] as String? ?? '',
        instrumentRef: json['instrumentRef'] as String?,
        issuer: json['issuer'] as String?,
        merchant: json['merchant'] as String?,
        balanceAfter: (json['balanceAfter'] as num?)?.toDouble(),
        entityType: EntityType.values.firstWhere(
          (e) => e.name == json['entityType'],
          orElse: () => EntityType.unknown,
        ),
        walletType: json['walletType'] as String?,
        billDueDate: json['billDueDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['billDueDate'] as int)
            : null,
        fastagWalletId: json['fastagWalletId'] as String?,
        vehicleNumber: json['vehicleNumber'] as String?,
        isOverridden: json['isOverridden'] as bool? ?? false,
        spendCategory: parseSpendCategory(json['spendCategory'] as String?),
      );
}

enum InvestmentKind { mutualFundSip, mutualFundPurchase, mutualFundRedemption, stockTrade, other }

extension InvestmentKindX on InvestmentKind {
  String get label {
    switch (this) {
      case InvestmentKind.mutualFundSip:
        return 'SIP';
      case InvestmentKind.mutualFundPurchase:
        return 'Mutual Fund Purchase';
      case InvestmentKind.mutualFundRedemption:
        return 'Redemption';
      case InvestmentKind.stockTrade:
        return 'Stock Trade';
      case InvestmentKind.other:
        return 'Other';
    }
  }

  bool get isRedemption => this == InvestmentKind.mutualFundRedemption;
}

class InvestmentEvent {
  final int smsId;
  final DateTime date;
  final double amount;
  final InvestmentKind kind;
  final String? fundOrScheme;
  final String? folioOrAccount;

  /// Number of units allotted/redeemed, if the SMS stated it or it could be
  /// derived from amount ÷ NAV.
  final double? units;

  /// Net asset value per unit at the time of this event, if stated.
  final double? nav;

  /// Asset management company / scheme provider (e.g. "Axis MF", "NPS").
  final String? amc;

  final String rawBody;

  /// True once the user has manually corrected [kind]/[fundOrScheme]/[amc]/
  /// [folioOrAccount] via SmsProvider.updateInvestment — see that method for
  /// why TransactionParserService never re-derives and overwrites this row
  /// after that.
  final bool isOverridden;

  InvestmentEvent({
    required this.smsId,
    required this.date,
    required this.amount,
    required this.kind,
    required this.rawBody,
    this.fundOrScheme,
    this.folioOrAccount,
    this.units,
    this.nav,
    this.amc,
    this.isOverridden = false,
  });

  /// Groups investment events by AMC/broker (e.g. "Axis MF", "Zerodha") for
  /// the Investments drilldown's "by AMC / merchant" view — falls back to
  /// the fund/scheme name, then a generic bucket, so an event with neither
  /// detected still lands somewhere instead of being dropped from grouping.
  ///
  /// Normalised (trimmed, whitespace-collapsed, lower-cased) so trivial
  /// formatting differences between two SMS from the same AMC — an extra
  /// space, a trailing period — don't split them into separate groups;
  /// [providerDisplayName] keeps the original casing for display.
  String get providerGroupKey =>
      (amc ?? fundOrScheme ?? 'Other').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String get providerDisplayName => (amc ?? fundOrScheme ?? 'Other').trim();

  Map<String, dynamic> toJson() => {
        'smsId': smsId,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'kind': kind.name,
        'fundOrScheme': fundOrScheme,
        'folioOrAccount': folioOrAccount,
        'units': units,
        'nav': nav,
        'amc': amc,
        'rawBody': rawBody,
        'isOverridden': isOverridden,
      };

  factory InvestmentEvent.fromJson(Map<String, dynamic> json) => InvestmentEvent(
        smsId: json['smsId'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
        amount: (json['amount'] as num).toDouble(),
        kind: InvestmentKind.values
            .firstWhere((e) => e.name == json['kind'], orElse: () => InvestmentKind.other),
        rawBody: json['rawBody'] as String? ?? '',
        fundOrScheme: json['fundOrScheme'] as String?,
        folioOrAccount: json['folioOrAccount'] as String?,
        units: (json['units'] as num?)?.toDouble(),
        nav: (json['nav'] as num?)?.toDouble(),
        amc: json['amc'] as String?,
        isOverridden: json['isOverridden'] as bool? ?? false,
      );
}
