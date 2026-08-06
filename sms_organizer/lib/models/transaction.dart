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
  });

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
  });

  /// Groups investment events by AMC/broker (e.g. "Axis MF", "Zerodha") for
  /// the Investments drilldown's "by AMC / merchant" view — falls back to
  /// the fund/scheme name, then a generic bucket, so an event with neither
  /// detected still lands somewhere instead of being dropped from grouping.
  String get providerGroupKey => amc ?? fundOrScheme ?? 'Other';

  String get providerDisplayName => amc ?? fundOrScheme ?? 'Other';

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
      );
}
