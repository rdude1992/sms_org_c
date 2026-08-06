import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
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
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE message_categories (
            sms_id INTEGER PRIMARY KEY,
            category TEXT NOT NULL
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
            raw_body TEXT
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
            nav REAL,
            amc TEXT,
            raw_body TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
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
      },
    );
  }

  // ---- Categories ----

  Future<void> saveCategory(int smsId, SmsCategory category) async {
    final db = await database;
    await db.insert(
      'message_categories',
      {'sms_id': smsId, 'category': category.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveCategoriesBulk(Map<int, SmsCategory> categories) async {
    final db = await database;
    final batch = db.batch();
    categories.forEach((id, cat) {
      batch.insert(
        'message_categories',
        {'sms_id': id, 'category': cat.name},
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

  // ---- Transactions ----

  Future<void> saveTransactionsBulk(List<Transaction> transactions) async {
    final db = await database;
    final batch = db.batch();
    for (final t in transactions) {
      batch.insert(
        'transactions',
        {
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
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
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
            ))
        .toList();
  }

  // ---- Investments ----

  Future<void> saveInvestmentsBulk(List<InvestmentEvent> events) async {
    final db = await database;
    final batch = db.batch();
    for (final e in events) {
      batch.insert(
        'investments',
        {
          'sms_id': e.smsId,
          'date': e.date.millisecondsSinceEpoch,
          'amount': e.amount,
          'kind': e.kind.name,
          'fund_or_scheme': e.fundOrScheme,
          'folio_or_account': e.folioOrAccount,
          'units': e.units,
          'nav': e.nav,
          'amc': e.amc,
          'raw_body': e.rawBody,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
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
              nav: row['nav'] as double?,
              amc: row['amc'] as String?,
              rawBody: row['raw_body'] as String? ?? '',
            ))
        .toList();
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

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('message_categories');
    await db.delete('transactions');
    await db.delete('investments');
  }
}
