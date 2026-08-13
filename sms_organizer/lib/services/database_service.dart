import 'package:path/path.dart' as p;
// sqflite re-exports its own `Transaction` (the db.transaction() callback
// type), which collides with our Transaction model from models/transaction.dart
// below — hidden since this file never references sqflite's directly.
import 'package:sqflite/sqflite.dart' hide Transaction;
import '../models/category.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';

/// Local cache layer. The Android SMS provider (content://sms) remains the
/// single source of truth for message content; this database only stores
/// derived data (category tags, parsed transactions/investments) so the app
/// doesn't have to re-run regex parsing over the full inbox on every launch,
/// and so backup/export has something structured to write out.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'sms_organizer.db');
    return openDatabase(
      path,
      version: 8,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE message_categories (
            sms_id INTEGER PRIMARY KEY,
            category TEXT NOT NULL,
            is_override INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            sms_id INTEGER PRIMARY KEY,
            date INTEGER NOT NULL,
            amount REAL NOT NULL,
            direction TEXT NOT NULL,
            instrument TEXT NOT NULL,
            instrument_ref TEXT,
            issuer TEXT,
            merchant TEXT,
            balance_after REAL,
            entity_type TEXT,
            wallet_type TEXT,
            bill_due_date INTEGER,
            fastag_wallet_id TEXT,
            vehicle_number TEXT,
            raw_body TEXT,
            is_override INTEGER NOT NULL DEFAULT 0,
            spend_category TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE investments (
            sms_id INTEGER PRIMARY KEY,
            date INTEGER NOT NULL,
            amount REAL NOT NULL,
            kind TEXT NOT NULL,
            fund_or_scheme TEXT,
            folio_or_account TEXT,
            units REAL,
            units_balance REAL,
            nav REAL,
            amc TEXT,
            raw_body TEXT,
            is_override INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE merchant_category_rules (
            merchant_key TEXT PRIMARY KEY,
            spend_category TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Existing installs from before the ported-regex update: add the
          // new columns (richer transaction/investment fields) and the meta
          // table (used to auto-trigger one recalculation below, since the
          // classifier logic itself changed and old cached categories are
          // now stale by definition).
          await db.execute('ALTER TABLE transactions ADD COLUMN entity_type TEXT');
          await db.execute('ALTER TABLE transactions ADD COLUMN wallet_type TEXT');
          await db.execute('ALTER TABLE transactions ADD COLUMN bill_due_date INTEGER');
          await db.execute('ALTER TABLE transactions ADD COLUMN fastag_wallet_id TEXT');
          await db.execute('ALTER TABLE transactions ADD COLUMN vehicle_number TEXT');
          await db.execute('ALTER TABLE investments ADD COLUMN units REAL');
          await db.execute('ALTER TABLE investments ADD COLUMN nav REAL');
          await db.execute('ALTER TABLE investments ADD COLUMN amc TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          // Lets a manually-corrected category (see SmsProvider.setMessageCategory)
          // be told apart from an auto-classified one, so cache wipes below can
          // preserve corrections instead of discarding them.
          await db.execute(
            'ALTER TABLE message_categories ADD COLUMN is_override INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          // Same idea as the message_categories column above, but for a
          // manually-corrected transaction (see SmsProvider.updateTransaction) —
          // direction/instrument/merchant/wallet fixes need to survive the
          // same cache wipes a category override does.
          await db.execute(
            'ALTER TABLE transactions ADD COLUMN is_override INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 5) {
          // Same idea again, for a manually-corrected investment (see
          // SmsProvider.updateInvestment) — kind/fund/AMC/folio fixes need to
          // survive the same cache wipes a category override does.
          await db.execute(
            'ALTER TABLE investments ADD COLUMN is_override INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          // Manually-assigned spend category (see SpendCategory) — always
          // user-set, never auto-detected, so it doesn't need its own
          // override flag: it rides along on the transaction row and
          // persists via the same is_override mechanism already in place.
          await db.execute('ALTER TABLE transactions ADD COLUMN spend_category TEXT');
        }
        if (oldVersion < 7) {
          // Merchant → SpendCategory associations learned from the user's
          // own tagging (see SmsProvider._rememberMerchantCategory) — not
          // touched by clearAll, same as any other user-set data.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS merchant_category_rules (
              merchant_key TEXT PRIMARY KEY,
              spend_category TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 8) {
          // A stated running/cumulative unit balance (e.g. "Balance Units
          // 205.177"), as opposed to `units`' this-installment-only delta —
          // see InvestmentEvent.unitsBalance and holdings_service.dart's
          // valueAsOf for why conflating the two double-counted every
          // holding whose SMS reports a running total.
          await db.execute('ALTER TABLE investments ADD COLUMN units_balance REAL');
        }
      },
    );
  }

  // ---- Categories ----

  /// [isOverride] marks a category the user set explicitly (via the "Change
  /// category" action), as opposed to one CategorizationService produced —
  /// see [clearAll], which preserves these rows.
  Future<void> saveCategory(int smsId, SmsCategory category, {bool isOverride = false}) async {
    final db = await database;
    await db.insert(
      'message_categories',
      {'sms_id': smsId, 'category': category.name, 'is_override': isOverride ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Always writes auto-classified rows (is_override = 0) — callers with a
  /// user-set category use [saveCategory] instead. Safe against clobbering
  /// an existing override because SmsProvider.refresh only ever calls this
  /// for ids that weren't already cached (override or not).
  Future<void> saveCategoriesBulk(Map<int, SmsCategory> categories) async {
    final db = await database;
    final batch = db.batch();
    categories.forEach((id, cat) {
      batch.insert(
        'message_categories',
        {'sms_id': id, 'category': cat.name, 'is_override': 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  Future<Map<int, SmsCategory>> loadCategories() async {
    final db = await database;
    final rows = await db.query('message_categories');
    final map = <int, SmsCategory>{};
    for (final row in rows) {
      map[row['sms_id'] as int] = SmsCategory.values.firstWhere(
        (e) => e.name == row['category'],
        orElse: () => SmsCategory.personal,
      );
    }
    return map;
  }

  /// ids of messages whose category was set manually rather than by
  /// CategorizationService — see [saveCategory].
  Future<Set<int>> loadOverriddenCategoryIds() async {
    final db = await database;
    final rows = await db.query('message_categories', columns: ['sms_id'], where: 'is_override = 1');
    return rows.map((row) => row['sms_id'] as int).toSet();
  }

  // ---- Transactions ----

  Map<String, dynamic> _transactionColumns(Transaction t, {required bool isOverride}) => {
        'sms_id': t.smsId,
        'date': t.date.millisecondsSinceEpoch,
        'amount': t.amount,
        'direction': t.direction.name,
        'instrument': t.instrument.name,
        'instrument_ref': t.instrumentRef,
        'issuer': t.issuer,
        'merchant': t.merchant,
        'balance_after': t.balanceAfter,
        'entity_type': t.entityType.name,
        'wallet_type': t.walletType,
        'bill_due_date': t.billDueDate?.millisecondsSinceEpoch,
        'fastag_wallet_id': t.fastagWalletId,
        'vehicle_number': t.vehicleNumber,
        'raw_body': t.rawBody,
        'is_override': isOverride ? 1 : 0,
        'spend_category': t.spendCategory?.name,
      };

  /// Always writes auto-parsed rows (is_override = 0) — callers with a
  /// user-corrected transaction use [saveTransaction] instead. Safe against
  /// clobbering an existing override for the same reason as
  /// [saveCategoriesBulk]: SmsProvider.refresh only calls this for ids that
  /// weren't already cached.
  Future<void> saveTransactionsBulk(List<Transaction> transactions) async {
    final db = await database;
    final batch = db.batch();
    for (final t in transactions) {
      batch.insert(
        'transactions',
        _transactionColumns(t, isOverride: false),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// [isOverride] marks a transaction the user corrected explicitly (via the
  /// "Edit transaction" action), as opposed to one TransactionParserService
  /// produced — see [clearAll], which preserves these rows.
  Future<void> saveTransaction(Transaction t, {bool isOverride = false}) async {
    final db = await database;
    await db.insert(
      'transactions',
      _transactionColumns(t, isOverride: isOverride),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Transaction>> loadTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');
    return rows
        .map((row) => Transaction(
              smsId: row['sms_id'] as int,
              date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
              amount: row['amount'] as double,
              direction: TxnDirection.values.firstWhere(
                (e) => e.name == row['direction'],
                orElse: () => TxnDirection.unknown,
              ),
              instrument: InstrumentType.values.firstWhere(
                (e) => e.name == row['instrument'],
                orElse: () => InstrumentType.unknown,
              ),
              instrumentRef: row['instrument_ref'] as String?,
              issuer: row['issuer'] as String?,
              merchant: row['merchant'] as String?,
              balanceAfter: row['balance_after'] as double?,
              entityType: EntityType.values.firstWhere(
                (e) => e.name == row['entity_type'],
                orElse: () => EntityType.unknown,
              ),
              walletType: row['wallet_type'] as String?,
              billDueDate: row['bill_due_date'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(row['bill_due_date'] as int)
                  : null,
              fastagWalletId: row['fastag_wallet_id'] as String?,
              vehicleNumber: row['vehicle_number'] as String?,
              rawBody: row['raw_body'] as String? ?? '',
              isOverridden: (row['is_override'] as int? ?? 0) == 1,
              spendCategory: parseSpendCategory(row['spend_category'] as String?),
            ))
        .toList();
  }

  // ---- Investments ----

  Map<String, dynamic> _investmentColumns(InvestmentEvent e, {required bool isOverride}) => {
        'sms_id': e.smsId,
        'date': e.date.millisecondsSinceEpoch,
        'amount': e.amount,
        'kind': e.kind.name,
        'fund_or_scheme': e.fundOrScheme,
        'folio_or_account': e.folioOrAccount,
        'units': e.units,
        'units_balance': e.unitsBalance,
        'nav': e.nav,
        'amc': e.amc,
        'raw_body': e.rawBody,
        'is_override': isOverride ? 1 : 0,
      };

  /// Always writes auto-parsed rows (is_override = 0) — callers with a
  /// user-corrected investment use [saveInvestment] instead. Safe against
  /// clobbering an existing override for the same reason as
  /// [saveCategoriesBulk]: SmsProvider.refresh only calls this for ids that
  /// weren't already cached.
  Future<void> saveInvestmentsBulk(List<InvestmentEvent> events) async {
    final db = await database;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(
        'investments',
        _investmentColumns(e, isOverride: false),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// [isOverride] marks an investment the user corrected explicitly (via the
  /// "Edit investment" action), as opposed to one TransactionParserService
  /// produced — see [clearAll], which preserves these rows.
  Future<void> saveInvestment(InvestmentEvent e, {bool isOverride = false}) async {
    final db = await database;
    await db.insert(
      'investments',
      _investmentColumns(e, isOverride: isOverride),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<InvestmentEvent>> loadInvestments() async {
    final db = await database;
    final rows = await db.query('investments', orderBy: 'date DESC');
    return rows
        .map((row) => InvestmentEvent(
              smsId: row['sms_id'] as int,
              date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
              amount: row['amount'] as double,
              kind: InvestmentKind.values.firstWhere(
                (e) => e.name == row['kind'],
                orElse: () => InvestmentKind.other,
              ),
              fundOrScheme: row['fund_or_scheme'] as String?,
              folioOrAccount: row['folio_or_account'] as String?,
              units: row['units'] as double?,
              unitsBalance: row['units_balance'] as double?,
              nav: row['nav'] as double?,
              amc: row['amc'] as String?,
              rawBody: row['raw_body'] as String? ?? '',
              isOverridden: (row['is_override'] as int? ?? 0) == 1,
            ))
        .toList();
  }

  // ---- Merchant category rules (learned from user tagging) ----

  /// Keyed by [Transaction.merchantGroupKey] — see
  /// SmsProvider._rememberMerchantCategory for how a rule gets learned and
  /// SmsProvider._applyMerchantRulesToUncategorised for how it then spreads
  /// to every other still-uncategorised transaction from that merchant.
  Future<Map<String, SpendCategory>> loadMerchantCategoryRules() async {
    final db = await database;
    final rows = await db.query('merchant_category_rules');
    final map = <String, SpendCategory>{};
    for (final row in rows) {
      final category = SpendCategory.values.where((c) => c.name == row['spend_category']);
      if (category.isNotEmpty) map[row['merchant_key'] as String] = category.first;
    }
    return map;
  }

  Future<void> saveMerchantCategoryRule(String merchantKey, SpendCategory category) async {
    final db = await database;
    await db.insert(
      'merchant_category_rules',
      {'merchant_key': merchantKey, 'spend_category': category.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMerchantCategoryRule(String merchantKey) async {
    final db = await database;
    await db.delete('merchant_category_rules', where: 'merchant_key = ?', whereArgs: [merchantKey]);
  }

  // ---- Meta (small key/value settings, e.g. categorizer cache version) ----

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears a single meta key so the next [getMeta] for it returns null —
  /// used to force a one-time pass to treat itself as "never run" (see
  /// SmsProvider._ensureCacheMatchesCurrentLogic forcing
  /// _backfillSpendCategories to re-run after a wipe) without needing to
  /// know or fake a specific "stale" version value.
  Future<void> deleteMeta(String key) async {
    final db = await database;
    await db.delete('meta', where: 'key = ?', whereArgs: [key]);
  }

  /// Removes cached derived data for messages that no longer exist on the
  /// device (e.g. deleted since the last sync), so stale transactions don't
  /// linger in Insights forever. Deletes one id at a time via a batch rather
  /// than a single "WHERE sms_id IN (...)" query — SQLite has a default
  /// parameter limit (~999) that a large stale set could exceed, and stale
  /// sets are expected to be small in practice (only messages removed since
  /// the last sync), so the per-row cost here is negligible.
  Future<void> deleteByIds(Set<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('message_categories', where: 'sms_id = ?', whereArgs: [id]);
      batch.delete('transactions', where: 'sms_id = ?', whereArgs: [id]);
      batch.delete('investments', where: 'sms_id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  /// Drops any cached transaction/investment parsed for [smsId], without
  /// touching its category row — used when a manual category override (see
  /// [saveCategory]) moves a message out of the transactional category, so
  /// stale spend/investment data doesn't linger in Insights.
  Future<void> deleteTransactionAndInvestment(int smsId) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('transactions', where: 'sms_id = ?', whereArgs: [smsId]);
    batch.delete('investments', where: 'sms_id = ?', whereArgs: [smsId]);
    await batch.commit(noResult: true);
  }

  /// Wipes auto-classified categories and auto-parsed transactions/
  /// investments, but keeps rows the user manually corrected (is_override =
  /// 1) — used by both the classifier-version-bump reprocess and the manual
  /// "Recalculate" button, neither of which should discard a correction the
  /// user made. SmsProvider.refresh() re-parses transaction/investment data
  /// for a preserved category that comes back without any (see there).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('message_categories', where: 'is_override = 0');
    await db.delete('transactions', where: 'is_override = 0');
    await db.delete('investments', where: 'is_override = 0');
  }
}
