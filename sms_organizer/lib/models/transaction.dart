enum TxnDirection { credit, debit, unknown }

enum InstrumentType { debitCard, creditCard, bankAccount, upi, unknown }

class Transaction {
  final int smsId;
  final DateTime date;
  final double amount;
  final TxnDirection direction;
  final InstrumentType instrument;

  /// e.g. last 4 digits of card/account, or the UPI handle if detected.
  final String? instrumentRef;

  /// Bank / issuer name if detected from the sender ID (e.g. "HDFC", "ICICI").
  final String? issuer;

  /// Merchant / payee name if the SMS format included one.
  final String? merchant;

  /// Available/remaining balance if the SMS mentioned it.
  final double? balanceAfter;

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
  });

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
      );
}

enum InvestmentKind { mutualFundSip, mutualFundPurchase, mutualFundRedemption, stockTrade, other }

class InvestmentEvent {
  final int smsId;
  final DateTime date;
  final double amount;
  final InvestmentKind kind;
  final String? fundOrScheme;
  final String? folioOrAccount;
  final String rawBody;

  InvestmentEvent({
    required this.smsId,
    required this.date,
    required this.amount,
    required this.kind,
    required this.rawBody,
    this.fundOrScheme,
    this.folioOrAccount,
  });

  Map<String, dynamic> toJson() => {
        'smsId': smsId,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'kind': kind.name,
        'fundOrScheme': fundOrScheme,
        'folioOrAccount': folioOrAccount,
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
      );
}
