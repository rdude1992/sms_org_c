import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/category.dart';
import '../models/sim_info.dart';
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

/// Which layout the Inbox tab shows — grouped-by-conversation ("Chats") or
/// a flat chronological list of every message ("Messages"). Persisted via
/// SmsProvider.setInboxView so the choice survives both switching tabs and
/// a cold app restart, not just staying alive in widget state.
enum InboxView { chats, messages }

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
  List<SimInfo> _activeSims = [];

  StreamSubscription? _incomingSub;

  // Multi-select state for the list views.
  final Set<int> selectedIds = {};
  bool get isSelecting => selectedIds.isNotEmpty;

  // Category filter shared by both Inbox layouts: the "all messages" flat
  // list and the "chats" conversation list (filters by each conversation's
  // latest message).
  SmsCategory? activeCategoryFilter;

  // Free-text search over the "all messages" list view — matches message
  // body, sender display name, and raw address.
  String searchQuery = '';

  // Separate free-text search over the "chats" list view — matches contact
  // display name, raw address, or any message body within the thread. Kept
  // independent from [searchQuery] so switching tabs doesn't carry a query
  // over to a list it wasn't typed into.
  String chatSearchQuery = '';

  // "Show unread only" toggle for the message list views. Shared across
  // both All Messages and Chats (unlike the search queries above, which
  // are deliberately per-tab) — "unread only" reads as one on/off
  // preference the user is setting, not text they'd type independently
  // into two different boxes.
  bool showUnreadOnly = false;

  /// Which layout the Inbox tab is currently showing. Loaded from disk in
  /// [initialize] and written back on every [setInboxView] call — see
  /// [InboxView] for why this needs to survive a cold restart, not just a
  /// tab switch.
  InboxView inboxView = InboxView.chats;
  static const _inboxViewPrefKey = 'inbox_view';

  // Pinned conversations and starred messages — the OS's SMS provider has
  // no columns for either, so both live purely in this app's own
  // SharedPreferences, loaded once in [initialize] and pruned of stale ids
  // (deleted messages/threads) on every [refresh].
  final Set<int> pinnedThreadIds = {};
  final Set<int> starredMessageIds = {};
  static const _pinnedPrefKey = 'pinned_thread_ids';
  static const _starredPrefKey = 'starred_message_ids';

  List<SmsMessage> get allMessages => _allMessages;

  /// [_allMessages] minus drafts — drafts aren't messages that were ever
  /// sent or received, so they're excluded from every regular list
  /// (conversations, All Messages, thread bubbles) and only surfaced
  /// through [drafts] itself.
  List<SmsMessage> get _sentOrReceived => _allMessages.where((m) => m.box != SmsBoxType.draft).toList();

  /// Every saved draft, newest first — see the Drafts screen.
  List<SmsMessage> get drafts {
    final list = _allMessages.where((m) => m.box == SmsBoxType.draft).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Every starred message, newest first — see the Starred screen.
  List<SmsMessage> get starredMessages {
    final list = _sentOrReceived.where((m) => starredMessageIds.contains(m.id)).toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Per-category message counts across every sent/received SMS (drafts
  /// excluded, same as [_sentOrReceived]) — used by the Settings screen's
  /// message-count summary. Sum of the values equals [totalMessageCount].
  Map<SmsCategory, int> get categoryCounts {
    final counts = {for (final c in SmsCategory.values) c: 0};
    for (final m in _sentOrReceived) {
      counts[m.category] = counts[m.category]! + 1;
    }
    return counts;
  }

  int get totalMessageCount => _sentOrReceived.length;

  bool isPinned(int threadId) => pinnedThreadIds.contains(threadId);
  bool isStarred(int messageId) => starredMessageIds.contains(messageId);
  List<Transaction> get transactions => _transactions;
  List<InvestmentEvent> get investments => _investments;
  List<SimInfo> get activeSims => _activeSims;
  bool get hasMultipleSims => _activeSims.length > 1;

  /// Filtered by [category] (unread-only and search query always apply) —
  /// lets the Inbox build one independently-filtered list per swipeable
  /// category tab rather than just a single currently-active one.
  List<SmsMessage> messagesForCategory(SmsCategory? category) {
    Iterable<SmsMessage> msgs = _sentOrReceived;
    if (category != null) {
      msgs = msgs.where((m) => m.category == category);
    }
    if (showUnreadOnly) {
      msgs = msgs.where((m) => m.isIncoming && !m.read);
    }
    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      msgs = msgs.where((m) =>
          m.body.toLowerCase().contains(query) ||
          m.address.toLowerCase().contains(query) ||
          displayNameFor(m.address).toLowerCase().contains(query));
    }
    return msgs.toList();
  }

  List<SmsConversation> get conversations {
    final Map<int, List<SmsMessage>> grouped = {};
    for (final m in _sentOrReceived) {
      grouped.putIfAbsent(m.threadId, () => []).add(m);
    }
    final result = grouped.entries.map((entry) {
      final msgs = entry.value..sort((a, b) => b.date.compareTo(a.date));
      return SmsConversation(threadId: entry.key, address: msgs.first.address, messages: msgs);
    }).toList();
    // Pinned conversations float to the top as a block, newest first within
    // each of the pinned/unpinned groups.
    result.sort((a, b) {
      final aPinned = pinnedThreadIds.contains(a.threadId);
      final bPinned = pinnedThreadIds.contains(b.threadId);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      return b.latest.date.compareTo(a.latest.date);
    });
    return result;
  }

  /// Filtered by [category] — see [messagesForCategory].
  List<SmsConversation> conversationsForCategory(SmsCategory? category) {
    Iterable<SmsConversation> convs = conversations;
    if (category != null) {
      convs = convs.where((c) => c.latest.category == category);
    }
    if (showUnreadOnly) {
      convs = convs.where((c) => c.unreadCount > 0);
    }
    final query = chatSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return convs.toList();
    return convs.where((c) {
      if (displayNameFor(c.address).toLowerCase().contains(query)) return true;
      if (c.address.toLowerCase().contains(query)) return true;
      return c.messages.any((m) => m.body.toLowerCase().contains(query));
    }).toList();
  }

  String displayNameFor(String address) => contactService.displayNameFor(address);

  /// Cold-start case: app was fully killed and relaunched by tapping a
  /// notification. Call once at startup.
  Future<int?> checkLaunchNotificationThreadId() => _platform.getLaunchNotificationThreadId();

  /// Warm case: app was already running (foreground/background, engine
  /// alive) when a notification was tapped. Subscribe once at startup.
  Stream<int> get onNotificationThreadTapped => _platform.onNotificationThreadTapped;

  InsightsSummary insightsSummary({
    DateTime? from,
    DateTime? to,
    TrendGranularity granularity = TrendGranularity.month,
  }) {
    return _insights.build(
      transactions: _transactions,
      investments: _investments,
      from: from,
      to: to,
      granularity: granularity,
    );
  }

  Future<Map<String, String?>?> checkLaunchComposeExtras() => _platform.getLaunchComposeExtras();

  Future<bool> checkIsDefaultSmsApp() async {
    isDefaultSmsApp = await _platform.isDefaultSmsApp();
    notifyListeners();
    return isDefaultSmsApp;
  }

  /// The real, current importance of [category]'s notification channel as
  /// configured in Android system settings — see
  /// [SmsPlatformService.getChannelImportance] for why this can disagree
  /// with [NotificationSettingsProvider.isMuted].
  Future<int> channelImportanceFor(SmsCategory category) =>
      _platform.getChannelImportance('sms_${category.name}');

  /// Deep-links into the OS's per-channel settings for [category] (sound,
  /// vibration, badge, priority conversation) — controls this app has no
  /// UI of its own for.
  Future<void> openChannelSettingsFor(SmsCategory category) =>
      _platform.openChannelSettings('sms_${category.name}');

  Future<void> initialize() async {
    isDefaultSmsApp = await _platform.isDefaultSmsApp();
    notifyListeners();
    await _loadInboxView();
    await _loadPinnedAndStarred();
    await contactService.load(_platform);
    await _loadActiveSims();
    await _ensureCacheMatchesCurrentLogic();
    await refresh();
    _listenForIncoming();
  }

  /// Best-effort: an empty result (no permission, single-SIM device) just
  /// means the SIM picker/badges stay hidden — never blocks startup.
  Future<void> _loadActiveSims() async {
    try {
      _activeSims = await _platform.getActiveSims();
    } catch (_) {
      _activeSims = [];
    }
    notifyListeners();
  }

  Future<void> _loadInboxView() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_inboxViewPrefKey);
    inboxView = InboxView.values.firstWhere(
      (v) => v.name == stored,
      orElse: () => InboxView.chats,
    );
    notifyListeners();
  }

  Future<void> setInboxView(InboxView view) async {
    if (inboxView == view) return;
    inboxView = view;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inboxViewPrefKey, view.name);
  }

  Future<void> _loadPinnedAndStarred() async {
    final prefs = await SharedPreferences.getInstance();
    pinnedThreadIds
      ..clear()
      ..addAll((prefs.getStringList(_pinnedPrefKey) ?? const []).map(int.parse));
    starredMessageIds
      ..clear()
      ..addAll((prefs.getStringList(_starredPrefKey) ?? const []).map(int.parse));
    notifyListeners();
  }

  Future<void> _savePinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedPrefKey, pinnedThreadIds.map((id) => id.toString()).toList());
  }

  Future<void> _saveStarred() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_starredPrefKey, starredMessageIds.map((id) => id.toString()).toList());
  }

  /// Drops pinned/starred ids that no longer correspond to anything on
  /// device (message or whole thread deleted since the last sync) — same
  /// idea as the cached-category pruning above, just for these two sets.
  Future<void> _prunePinnedAndStarred(Set<int> rawMessageIds) async {
    final liveThreadIds = _allMessages.map((m) => m.threadId).toSet();

    final staleStarred = starredMessageIds.where((id) => !rawMessageIds.contains(id)).toList();
    if (staleStarred.isNotEmpty) {
      starredMessageIds.removeAll(staleStarred);
      await _saveStarred();
    }

    final stalePinned = pinnedThreadIds.where((id) => !liveThreadIds.contains(id)).toList();
    if (stalePinned.isNotEmpty) {
      pinnedThreadIds.removeAll(stalePinned);
      await _savePinned();
    }
  }

  Future<void> togglePinned(int threadId) async {
    if (!pinnedThreadIds.remove(threadId)) pinnedThreadIds.add(threadId);
    notifyListeners();
    await _savePinned();
  }

  Future<void> toggleStarred(int messageId) async {
    if (!starredMessageIds.remove(messageId)) starredMessageIds.add(messageId);
    notifyListeners();
    await _saveStarred();
  }

  /// Incremental sync deliberately never re-evaluates a cached category
  /// once written (see refresh() below) — that's what makes it fast, but
  /// it also means a cache built under old classifier logic would
  /// otherwise be reused forever even after the logic changes. This runs
  /// once per logic version bump (see CategorizationService.version) and
  /// wipes the cache so the next refresh() reprocesses everything fresh.
  /// A no-op on a brand-new install, since clearing empty tables is free.
  Future<void> _ensureCacheMatchesCurrentLogic() async {
    final storedVersion = await _db.getMeta('categorizer_version');
    final currentVersion = CategorizationService.version.toString();
    if (storedVersion == currentVersion) return;

    await _db.clearAll();
    await _db.setMeta('categorizer_version', currentVersion);
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
      final overriddenIds = await _db.loadOverriddenCategoryIds();
      final cachedTransactions = await _db.loadTransactions();
      final cachedInvestments = await _db.loadInvestments();
      final cachedTxnIds = cachedTransactions.map((t) => t.smsId).toSet();
      final cachedInvIds = cachedInvestments.map((i) => i.smsId).toSet();

      final newCategories = <int, SmsCategory>{};
      final newTransactions = <Transaction>[];
      final newInvestments = <InvestmentEvent>[];

      for (final m in messages) {
        final cached = cachedCategories[m.id];
        if (cached != null) {
          m.category = cached;
          m.isCategoryOverridden = overriddenIds.contains(m.id);
          // A cached transactional category can end up without any parsed
          // transaction/investment row — e.g. a manual override just made it
          // transactional (see setMessageCategory), or it survived a
          // classifier-version-bump wipe that cleared parsed data but kept
          // overridden categories (see DatabaseService.clearAll). Parse it
          // now rather than leaving it silently missing from Insights forever.
          if (cached == SmsCategory.transactional &&
              !cachedTxnIds.contains(m.id) &&
              !cachedInvIds.contains(m.id)) {
            final inv = _txnParser.parseInvestment(m);
            if (inv != null) {
              newInvestments.add(inv);
            } else {
              final txn = _txnParser.parseTransaction(m);
              if (txn != null) newTransactions.add(txn);
            }
          }
          continue; // already processed in a previous sync
        }

        m.category = _categorizer.categorize(m);
        newCategories[m.id] = m.category;

        if (m.category == SmsCategory.transactional) {
          // Investment first, generic transaction only as a fallback: a SIP/
          // mutual-fund/stock-trade confirmation (the AMC or broker's own
          // SMS, not the bank's separate debit alert for the same money)
          // always also has an amount, so it would otherwise pass
          // parseTransaction's bare "has an amount" gate too — recording it
          // as BOTH a generic Transaction (counted in Debited/By-card
          // totals) AND an InvestmentEvent (counted in Invested totals)
          // double-counts every rupee ever invested. The bank-side debit
          // alert for the same real-world payment is a separate SMS with
          // its own account/UPI language, not SIP/folio/NAV wording, so it
          // never matches parseInvestment and still comes through as a
          // normal Transaction below.
          final inv = _txnParser.parseInvestment(m);
          if (inv != null) {
            newInvestments.add(inv);
          } else {
            final txn = _txnParser.parseTransaction(m);
            if (txn != null) newTransactions.add(txn);
          }
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
      await _prunePinnedAndStarred(rawIds);
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

  // ---- Single-item actions (swipe actions, long-press context menu) ----

  Future<void> deleteMessage(int id) async {
    await _platform.deleteMessages([id]);
    await refresh();
  }

  Future<void> deleteConversation(SmsConversation conversation) async {
    final ids = conversation.messages.map((m) => m.id).toList();
    await _platform.deleteMessages(ids);
    await refresh();
  }

  Future<void> setMessageRead(int id, bool read) async {
    await _platform.markRead([id], read);
    await refresh();
  }

  Future<void> setConversationRead(SmsConversation conversation, bool read) async {
    final ids = conversation.messages.where((m) => m.isIncoming).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    await _platform.markRead(ids, read);
    await refresh();
  }

  /// Marks every unread incoming message in [threadId] as read. Call this
  /// when a thread is opened — ThreadScreen previously never did, so
  /// messages stayed "unread" (device SMS store included) no matter how
  /// many times you opened the conversation.
  ///
  /// Writing to the OS's own SMS store only actually takes effect when
  /// this app is the default SMS app — same restriction every other write
  /// (send, delete, the multi-select mark-read above) already has, and the
  /// OS enforces it, not us. This is called automatically on every thread
  /// open rather than from an explicit user action, so a failure (not
  /// default, transient platform error) is swallowed rather than
  /// interrupting the read: the unread badge just won't clear until the
  /// app is made default.
  Future<void> markThreadRead(int threadId) async {
    final unreadIds = _allMessages
        .where((m) => m.threadId == threadId && m.isIncoming && !m.read)
        .map((m) => m.id)
        .toList();
    if (unreadIds.isEmpty) return;
    try {
      await _platform.markRead(unreadIds, true);
    } catch (_) {
      return;
    }
    await refresh();
  }

  // ---- Sending / drafts ----

  Future<bool> sendSms(String address, String body, {int? subscriptionId}) async {
    final ok = await _platform.sendSms(address, body, subscriptionId: subscriptionId);
    if (ok) await refresh();
    return ok;
  }

  Future<void> saveDraft(String address, String body, {int? existingId}) async {
    await _platform.saveDraft(address, body, existingId: existingId);
    await refresh();
  }

  /// User-driven correction for when CategorizationService got a message's
  /// category wrong. Persists immediately as an override (see
  /// DatabaseService.saveCategory) so it's never silently re-classified or
  /// discarded by a later cache wipe — unlike an auto-assigned category,
  /// this one is treated as the source of truth going forward.
  ///
  /// Also keeps derived Insights data in sync with the correction: moving a
  /// message out of Transactions drops its parsed transaction/investment,
  /// and moving one in attempts to parse it fresh.
  Future<void> setMessageCategory(SmsMessage message, SmsCategory category) async {
    final previousCategory = message.category;
    if (previousCategory == category && message.isCategoryOverridden) return;

    message.category = category;
    message.isCategoryOverridden = true;
    notifyListeners();
    await _db.saveCategory(message.id, category, isOverride: true);

    final wasTransactional = previousCategory == SmsCategory.transactional;
    final isTransactional = category == SmsCategory.transactional;
    if (wasTransactional && !isTransactional) {
      await _db.deleteTransactionAndInvestment(message.id);
      _transactions.removeWhere((t) => t.smsId == message.id);
      _investments.removeWhere((i) => i.smsId == message.id);
      notifyListeners();
    } else if (!wasTransactional && isTransactional) {
      final inv = _txnParser.parseInvestment(message);
      if (inv != null) {
        await _db.saveInvestmentsBulk([inv]);
        _investments.add(inv);
      } else {
        final txn = _txnParser.parseTransaction(message);
        if (txn != null) {
          await _db.saveTransactionsBulk([txn]);
          _transactions.add(txn);
        }
      }
      notifyListeners();
    }
  }

  void setCategoryFilter(SmsCategory? category) {
    activeCategoryFilter = category;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void setChatSearchQuery(String query) {
    chatSearchQuery = query;
    notifyListeners();
  }

  void setShowUnreadOnly(bool value) {
    showUnreadOnly = value;
    notifyListeners();
  }

  Future<void> restoreFromBackup(BackupBundle bundle) async {
    _allMessages = bundle.messages;
    _transactions = bundle.transactions;
    _investments = bundle.investments;
    // Manually-corrected categories are restored as overrides too, so a
    // backup/restore round-trip doesn't quietly forget a correction the user
    // made before exporting — see setMessageCategory.
    final autoCategories = <int, SmsCategory>{};
    for (final m in bundle.messages) {
      if (m.isCategoryOverridden) {
        await _db.saveCategory(m.id, m.category, isOverride: true);
      } else {
        autoCategories[m.id] = m.category;
      }
    }
    if (autoCategories.isNotEmpty) await _db.saveCategoriesBulk(autoCategories);
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
