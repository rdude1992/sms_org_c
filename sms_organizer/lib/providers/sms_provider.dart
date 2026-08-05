import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../models/transaction.dart';
import '../services/backup_service.dart';
import '../services/categorization_service.dart';
import '../services/contact_service.dart';
import '../services/database_service.dart';
import '../services/insights_service.dart';
import '../services/sms_platform_service.dart';
import '../services/transaction_parser_service.dart';

enum LoadState { idle, loading, ready, error }

class SmsProvider extends ChangeNotifier {
  final SmsPlatformService _platform = SmsPlatformService.instance;
  final CategorizationService _categorizer = CategorizationService();
  final TransactionParserService _txnParser = TransactionParserService();
  final InsightsService _insights = InsightsService();
  final DatabaseService _db = DatabaseService.instance;
  final BackupService backup = BackupService();
  final ContactService contactService = ContactService();

  LoadState state = LoadState.idle;
  String? error;
  bool isDefaultSmsApp = false;

  List<SmsMessage> _allMessages = [];
  List<Transaction> _transactions = [];
  List<InvestmentEvent> _investments = [];

  StreamSubscription? _incomingSub;

  // Multi-select state for the list views.
  final Set<int> selectedIds = {};
  bool get isSelecting => selectedIds.isNotEmpty;

  // Category filter for the "all messages" list view.
  SmsCategory? activeCategoryFilter;

  List<SmsMessage> get allMessages => _allMessages;
  List<Transaction> get transactions => _transactions;
  List<InvestmentEvent> get investments => _investments;

  List<SmsMessage> get filteredMessages {
    if (activeCategoryFilter == null) return _allMessages;
    return _allMessages.where((m) => m.category == activeCategoryFilter).toList();
  }

  List<SmsConversation> get conversations {
    final Map<int, List<SmsMessage>> grouped = {};
    for (final m in _allMessages) {
      grouped.putIfAbsent(m.threadId, () => []).add(m);
    }
    final result = grouped.entries.map((entry) {
      final msgs = entry.value..sort((a, b) => b.date.compareTo(a.date));
      return SmsConversation(threadId: entry.key, address: msgs.first.address, messages: msgs);
    }).toList();
    result.sort((a, b) => b.latest.date.compareTo(a.latest.date));
    return result;
  }

  String displayNameFor(String address) => contactService.displayNameFor(address);

  /// Cold-start case: app was fully killed and relaunched by tapping a
  /// notification. Call once at startup.
  Future<int?> checkLaunchNotificationThreadId() => _platform.getLaunchNotificationThreadId();

  /// Warm case: app was already running (foreground/background, engine
  /// alive) when a notification was tapped. Subscribe once at startup.
  Stream<int> get onNotificationThreadTapped => _platform.onNotificationThreadTapped;

  InsightsSummary insightsSummary({DateTime? from, DateTime? to}) {
    return _insights.build(transactions: _transactions, investments: _investments, from: from, to: to);
  }

  Future<Map<String, String?>?> checkLaunchComposeExtras() => _platform.getLaunchComposeExtras();

  Future<bool> checkIsDefaultSmsApp() async {
    isDefaultSmsApp = await _platform.isDefaultSmsApp();
    notifyListeners();
    return isDefaultSmsApp;
  }

  Future<void> initialize() async {
    isDefaultSmsApp = await _platform.isDefaultSmsApp();
    notifyListeners();
    await contactService.load(_platform);
    await refresh();
    _listenForIncoming();
  }

  Future<bool> requestDefaultSmsRole() async {
    await _platform.requestDefaultSmsApp();
    isDefaultSmsApp = await _platform.isDefaultSmsApp();
    notifyListeners();
    if (isDefaultSmsApp) {
      await refresh();
    }
    return isDefaultSmsApp;
  }

  Future<void> refresh() async {
    state = LoadState.loading;
    notifyListeners();
    try {
      // Raw content always comes fresh from content://sms — we don't cache
      // message bodies/addresses/dates, only the derived data below. This
      // fetch itself is unavoidable on every refresh; what we're avoiding
      // is re-running regex classification/parsing over the *entire*
      // inbox every single time.
      final messages = await _platform.getAllMessages();
      final rawIds = messages.map((m) => m.id).toSet();

      // Cache-first: everything we've already classified/parsed in a
      // previous sync is reused as-is. Only messages NOT present in these
      // maps (i.e. arrived since the last sync) get run through the
      // classifier/parser below.
      final cachedCategories = await _db.loadCategories();
      final cachedTransactions = await _db.loadTransactions();
      final cachedInvestments = await _db.loadInvestments();

      final newCategories = <int, SmsCategory>{};
      final newTransactions = <Transaction>[];
      final newInvestments = <InvestmentEvent>[];

      for (final m in messages) {
        final cached = cachedCategories[m.id];
        if (cached != null) {
          m.category = cached;
          continue; // already processed in a previous sync
        }

        m.category = _categorizer.categorize(m);
        newCategories[m.id] = m.category;

        if (m.category == SmsCategory.transactional) {
          final txn = _txnParser.parseTransaction(m);
          if (txn != null) newTransactions.add(txn);
          final inv = _txnParser.parseInvestment(m);
          if (inv != null) newInvestments.add(inv);
        }
      }

      // Persist only what's new — no point rewriting rows that haven't
      // changed on every single refresh.
      if (newCategories.isNotEmpty) await _db.saveCategoriesBulk(newCategories);
      if (newTransactions.isNotEmpty) await _db.saveTransactionsBulk(newTransactions);
      if (newInvestments.isNotEmpty) await _db.saveInvestmentsBulk(newInvestments);

      // Prune cache entries for messages that no longer exist on-device
      // (e.g. deleted since the last sync), so a stale transaction doesn't
      // linger in Insights forever.
      final staleIds = cachedCategories.keys.where((id) => !rawIds.contains(id)).toSet();
      if (staleIds.isNotEmpty) await _db.deleteByIds(staleIds);

      _allMessages = messages;
      _transactions = [
        ...cachedTransactions.where((t) => rawIds.contains(t.smsId)),
        ...newTransactions,
      ];
      _investments = [
        ...cachedInvestments.where((i) => rawIds.contains(i.smsId)),
        ...newInvestments,
      ];
      state = LoadState.ready;
      error = null;
    } catch (e) {
      state = LoadState.error;
      error = e.toString();
    }
    notifyListeners();
  }

  /// Manual escape hatch: wipes the local cache and reprocesses everything
  /// from scratch. Use this after tuning the categorisation/parsing regex,
  /// or if something looks miscategorised and you want a clean re-scan
  /// rather than waiting for incremental sync to naturally correct it (it
  /// won't, by design — cached entries are never automatically
  /// re-evaluated once written).
  Future<void> recalculateAll() async {
    await _db.clearAll();
    await refresh();
  }

  void _listenForIncoming() {
    _incomingSub = _platform.onIncomingSms.listen((_) {
      // Any live event triggers a full re-sync rather than trying to
      // incrementally patch state — simpler and cheap enough for typical
      // inbox sizes, and avoids drift between the provider's cache and
      // the OS-owned SMS table. Notification posting itself happens
      // entirely natively now (see IncomingSmsNotifier.kt) so it works
      // even when this Dart code isn't running at all — this listener is
      // purely about keeping the in-app UI live when it is.
      refresh();
    });
  }

  // ---- Multi-select ----

  void toggleSelected(int id) {
    if (selectedIds.contains(id)) {
      selectedIds.remove(id);
    } else {
      selectedIds.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    selectedIds.clear();
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    await _platform.deleteMessages(selectedIds.toList());
    clearSelection();
    await refresh();
  }

  Future<void> markSelectedRead(bool read) async {
    await _platform.markRead(selectedIds.toList(), read);
    clearSelection();
    await refresh();
  }

  // ---- Sending / drafts ----

  Future<bool> sendSms(String address, String body) async {
    final ok = await _platform.sendSms(address, body);
    if (ok) await refresh();
    return ok;
  }

  Future<void> saveDraft(String address, String body, {int? existingId}) async {
    await _platform.saveDraft(address, body, existingId: existingId);
    await refresh();
  }

  void setCategoryFilter(SmsCategory? category) {
    activeCategoryFilter = category;
    notifyListeners();
  }

  Future<void> restoreFromBackup(BackupBundle bundle) async {
    _allMessages = bundle.messages;
    _transactions = bundle.transactions;
    _investments = bundle.investments;
    await _db.saveCategoriesBulk({for (final m in bundle.messages) m.id: m.category});
    await _db.saveTransactionsBulk(bundle.transactions);
    await _db.saveInvestmentsBulk(bundle.investments);
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }
}
