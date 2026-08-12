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
import '../services/spend_category_detector.dart';
import '../services/transaction_parser_service.dart';

enum LoadState { idle, loading, ready, error }

/// Which layout the Inbox tab shows — grouped-by-conversation ("Chats") or
/// a flat chronological list of every message ("Messages"). Persisted via
/// SmsProvider.setInboxView so the choice survives both switching tabs and
/// a cold app restart, not just staying alive in widget state.
enum InboxView { chats, messages }

/// Sentinel default for [SmsProvider.updateTransactionsBulk]'s
/// [spendCategory] param, so "not passed" (leave each transaction's spend
/// category as-is) is distinguishable from an explicit `null` ("clear to
/// Uncategorised").
const Object keepSpendCategory = Object();

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

  // Merchant -> SpendCategory associations learned from the user's own
  // tagging (see _rememberMerchantCategory), keyed by
  // Transaction.merchantGroupKey. Consulted as a fallback wherever a
  // transaction gets auto-tagged (SpendCategoryDetector's static rules
  // come first) and re-applied to every matching still-uncategorised
  // transaction whenever a rule changes — see
  // _applyMerchantRulesToUncategorised.
  Map<String, SpendCategory> _merchantCategoryRules = {};

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

  /// Looks up the SMS a parsed [Transaction] came from — e.g. so an "this
  /// isn't a transaction" action can reach the message's category to
  /// correct it (see setMessageCategory). Null if the message has since
  /// been deleted from the device.
  SmsMessage? messageById(int id) {
    for (final m in _allMessages) {
      if (m.id == id) return m;
    }
    return null;
  }

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

  /// Opens the system Contacts app's detail page for whichever saved
  /// contact matches [address] — see ThreadScreen's tap-to-open-contact
  /// action on the phone number line under the conversation title.
  Future<bool> openContact(String address) => _platform.openContact(address);

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
    // Loaded before refresh() so freshly-parsed transactions can already
    // consult learned merchant rules as a fallback (see refresh()'s
    // _applyLearnedMerchantCategory calls), not just the one-time backfill
    // pass below.
    _merchantCategoryRules = await _db.loadMerchantCategoryRules();
    await refresh();
    await _backfillSpendCategories();
    await _applyMerchantRulesToUncategorised();
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
    // clearAll() just deleted every non-override transaction's
    // spend_category along with its row. _backfillSpendCategories() below
    // (called later in initialize()) is the only thing that re-tags those
    // — but it's gated on its own, unrelated SpendCategoryDetector.version
    // meta key, which this wipe didn't touch. Left alone, that gate would
    // still read as "already backfilled" from before this wipe and skip
    // re-running entirely, leaving every auto-tagged transaction stuck on
    // "Uncategorised" until SpendCategoryDetector's own logic happens to
    // change next. Clearing the key forces that pass to treat itself as
    // never having run, so it actually re-tags the freshly-reparsed data.
    await _db.deleteMeta('spend_category_version');
  }

  /// One-time pass tagging already-cached transactions with a
  /// [SpendCategory] that [SpendCategoryDetector] can confidently infer
  /// from their merchant/body. Without this, only transactions parsed
  /// *after* SpendCategoryDetector's rules existed would ever get an
  /// automatic category — anything synced earlier (the bulk of a real
  /// user's ~2000-message history) would stay "Uncategorised" forever,
  /// since refresh() never re-processes a transaction once it's cached.
  ///
  /// Runs once per [SpendCategoryDetector.version] bump, then no-ops until
  /// the rules next change (tracked the same way as
  /// [_ensureCacheMatchesCurrentLogic]'s categorizer-version gate, just
  /// without wiping anything — this only ever fills in a blank
  /// [Transaction.spendCategory], never overwrites one the user set or a
  /// transaction they've otherwise corrected).
  Future<void> _backfillSpendCategories() async {
    final storedVersion = await _db.getMeta('spend_category_version');
    final currentVersion = SpendCategoryDetector.version.toString();
    if (storedVersion != currentVersion) {
      final updated = <Transaction>[];
      for (var i = 0; i < _transactions.length; i++) {
        final t = _transactions[i];
        if (t.spendCategory != null || t.isOverridden) continue;
        final detected = SpendCategoryDetector.detect(t);
        if (detected == null) continue;
        final withCategory = t.copyWith(spendCategory: detected);
        _transactions[i] = withCategory;
        updated.add(withCategory);
      }
      if (updated.isNotEmpty) {
        await _db.saveTransactionsBulk(updated);
        notifyListeners();
      }
      await _db.setMeta('spend_category_version', currentVersion);
    }
  }

  /// Fills in [t]'s [Transaction.spendCategory] from a learned merchant
  /// rule when [SpendCategoryDetector]'s static rules didn't already match
  /// — the parse-time half of "tag one, apply everywhere" (the other half,
  /// [_applyMerchantRulesToUncategorised], is the retroactive backfill for
  /// transactions that already existed when the rule was learned). Only
  /// ever fills a blank category, exactly like SpendCategoryDetector
  /// itself, so it never overwrites anything and never sets
  /// [Transaction.isOverridden].
  Transaction _applyLearnedMerchantCategory(Transaction t) {
    if (t.spendCategory != null) return t;
    final key = t.merchantGroupKey;
    if (key == null) return t;
    final rule = _merchantCategoryRules[key];
    if (rule == null) return t;
    return t.copyWith(spendCategory: rule);
  }

  /// Records (or forgets) a merchant -> [SpendCategory] association from an
  /// explicit user tagging — called from every place a user sets a
  /// transaction's spend category (updateTransaction,
  /// setSpendCategoryForTransactions, updateTransactionsBulk). Returns
  /// whether the rule set actually changed, so callers only pay for
  /// [_applyMerchantRulesToUncategorised]'s retroactive scan when there's
  /// actually something new to spread.
  ///
  /// Clearing back to Uncategorised ([category] null) forgets any existing
  /// rule for that merchant rather than leaving it in place — the user
  /// just said this merchant's category isn't obvious/consistent, so
  /// letting it keep auto-tagging future transactions the same way would
  /// silence exactly the signal they gave.
  Future<bool> _rememberMerchantCategory(Transaction t, SpendCategory? category) async {
    final key = t.merchantGroupKey;
    if (key == null) return false;
    if (category == null) {
      if (_merchantCategoryRules.remove(key) == null) return false;
      await _db.deleteMerchantCategoryRule(key);
      return false;
    }
    if (_merchantCategoryRules[key] == category) return false;
    _merchantCategoryRules[key] = category;
    await _db.saveMerchantCategoryRule(key, category);
    return true;
  }

  /// Applies every learned merchant rule to every transaction that's still
  /// Uncategorised and not user-overridden — see _rememberMerchantCategory
  /// (which updates [_merchantCategoryRules]) and
  /// [_applyLearnedMerchantCategory] (the equivalent fallback applied to a
  /// transaction as it's first parsed, so this backfill only has to cover
  /// transactions that already existed before the rule did).
  Future<void> _applyMerchantRulesToUncategorised() async {
    if (_merchantCategoryRules.isEmpty) return;
    final updated = <Transaction>[];
    for (var i = 0; i < _transactions.length; i++) {
      final t = _transactions[i];
      if (t.spendCategory != null || t.isOverridden) continue;
      final rule = _merchantCategoryRules[t.merchantGroupKey];
      if (rule == null) continue;
      final withCategory = t.copyWith(spendCategory: rule);
      _transactions[i] = withCategory;
      updated.add(withCategory);
    }
    if (updated.isNotEmpty) {
      await _db.saveTransactionsBulk(updated);
      notifyListeners();
    }
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
              if (txn != null) newTransactions.add(_applyLearnedMerchantCategory(txn));
            }
          } else if (cached == SmsCategory.updates && !cachedInvIds.contains(m.id)) {
            // A periodic investment value statement (NPS/Protean's
            // "Investment value ... as on ... is Rs X") — categorized
            // updates, not transactional, since no money moved, but still
            // worth recording as an InvestmentEvent so holdings_service.dart
            // can use it as a value checkpoint. See parseInvestmentValuation.
            final valuation = _txnParser.parseInvestmentValuation(m);
            if (valuation != null) newInvestments.add(valuation);
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
            if (txn != null) newTransactions.add(_applyLearnedMerchantCategory(txn));
          }
        } else if (m.category == SmsCategory.updates) {
          final valuation = _txnParser.parseInvestmentValuation(m);
          if (valuation != null) newInvestments.add(valuation);
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
  ///
  /// Mirrors initialize()'s post-wipe sequence, not just clearAll()+refresh()
  /// — clearAll() deletes every non-override transaction's spend_category
  /// along with its row, and only _backfillSpendCategories/
  /// _applyMerchantRulesToUncategorised actually refill it. Skipping those
  /// (as an earlier version of this method did) left every auto-tagged
  /// transaction stuck "Uncategorised" after a manual recalculate, with no
  /// way to self-heal short of a full app restart.
  Future<void> recalculateAll() async {
    await _db.clearAll();
    await _db.deleteMeta('spend_category_version');
    await refresh();
    await _backfillSpendCategories();
    await _applyMerchantRulesToUncategorised();
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

  /// The "select all" side of the Inbox multi-select bar's select-all/none
  /// toggle — replaces the current selection outright with [ids], which the
  /// caller has already narrowed to whatever's actually visible (the active
  /// category tab, search query, and unread-only filter), not literally
  /// every message on device.
  void selectIds(Iterable<int> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
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

  /// Bulk equivalent of [setMessageCategory] for the current multi-select
  /// — see MultiSelectAppBar's "Set category" action on the Inbox's flat
  /// Messages list. Exists because manually categorising a couple thousand
  /// pre-existing SMS one at a time isn't realistic; this lets a batch of
  /// mis-filed messages (e.g. every promo SMS a particular sender ever
  /// sent) get corrected in one pass instead. Routes through
  /// setMessageCategory per message so each one gets the same
  /// override-persistence and transaction/investment re-parse it would from
  /// a single manual correction.
  Future<void> setSelectedCategory(SmsCategory category) async {
    final ids = selectedIds.toList();
    clearSelection();
    for (final id in ids) {
      final message = messageById(id);
      if (message != null) await setMessageCategory(message, category);
    }
  }

  /// Bulk equivalent of the spend-category field in [updateTransaction] —
  /// see TransactionListScreen's multi-select "Set category" action, for
  /// tagging a batch of transactions SpendCategoryDetector left
  /// "Uncategorised" (or got wrong) in one pass instead of one at a time.
  ///
  /// Also pins the parent message's category as an override, same as
  /// [updateTransaction] does — without this, a later
  /// [DatabaseService.clearAll] wipe (see
  /// [_ensureCacheMatchesCurrentLogic]) would delete this message's
  /// `message_categories` row (still `is_override = 0`, since nothing here
  /// had touched it) even though its `transactions` row correctly survived
  /// as an override. `refresh()` would then find no cached category for
  /// it, re-classify and re-parse it from scratch as a brand-new,
  /// un-tagged `Transaction`, and `saveTransactionsBulk`'s `INSERT OR
  /// REPLACE` would silently overwrite the still-good override row with
  /// that blank one — destroying a spend category the user explicitly set,
  /// not just hiding it.
  Future<void> setSpendCategoryForTransactions(List<int> smsIds, SpendCategory? category) async {
    var ruleChanged = false;
    for (final id in smsIds) {
      final index = _transactions.indexWhere((t) => t.smsId == id);
      if (index == -1) continue;
      final updated = _transactions[index].copyWith(spendCategory: category, isOverridden: true);
      _transactions[index] = updated;
      await _db.saveTransaction(updated, isOverride: true);
      await _db.saveCategory(id, SmsCategory.transactional, isOverride: true);
      final message = messageById(id);
      if (message != null) {
        message.category = SmsCategory.transactional;
        message.isCategoryOverridden = true;
      }
      if (await _rememberMerchantCategory(updated, category)) ruleChanged = true;
    }
    if (ruleChanged) await _applyMerchantRulesToUncategorised();
    notifyListeners();
  }

  /// Bulk equivalent of [setMessageCategory] for TransactionListScreen's and
  /// InvestmentListScreen's multi-select "Not a transaction?"/"Not an
  /// investment?" actions — moves every message in [smsIds] to [category] in
  /// one pass, the same way the single-item TransactionTile/InvestmentTile
  /// action does for one. Despite the name, this only ever touches
  /// [SmsMessage.category] (via [setMessageCategory]), so it works
  /// identically for a batch of transaction or investment ids. Kept separate
  /// from [setSelectedCategory] because that one is hard-wired to
  /// [selectedIds] (the Inbox's own cross-screen selection state) — both
  /// list screens deliberately keep their selection local (see
  /// TransactionListScreen/InvestmentListScreen), so this takes the id list
  /// explicitly instead.
  Future<void> setCategoryForTransactions(List<int> smsIds, SmsCategory category) async {
    for (final id in smsIds) {
      final message = messageById(id);
      if (message != null) await setMessageCategory(message, category);
    }
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

  /// Re-sends a message whose [SmsMessage.sendState] is
  /// [OutgoingSendState.failed] — the radio never got it in the first place,
  /// so this is a plain resend rather than something that could double-
  /// deliver to the recipient (contrast [OutgoingSendState.notDelivered],
  /// where it did send and a resend risks exactly that — no retry offered
  /// for that state, see MessageBubble). Drops the failed row first so it
  /// doesn't linger alongside the new attempt.
  Future<bool> retrySend(SmsMessage message) async {
    int? subscriptionId;
    if (message.simSlot != null) {
      final sim = _activeSims.where((s) => s.slotIndex == message.simSlot);
      if (sim.isNotEmpty) subscriptionId = sim.first.subscriptionId;
    }
    await _platform.deleteMessages([message.id]);
    return sendSms(message.address, message.body, subscriptionId: subscriptionId);
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
        final parsed = _txnParser.parseTransaction(message);
        if (parsed != null) {
          final txn = _applyLearnedMerchantCategory(parsed);
          await _db.saveTransactionsBulk([txn]);
          _transactions.add(txn);
        }
      }
      notifyListeners();
    }
  }

  /// User-driven correction for when TransactionParserService mis-detected
  /// [transaction]'s type, instrument, merchant, or wallet — the case where
  /// the message genuinely is a transaction, but it's filed under the wrong
  /// Credited/Debited tab, the wrong Cards & Accounts bucket, or the wrong
  /// merchant. Also where [spendCategory] gets set from the edit form, and
  /// (see [assignInstrumentToTransactions]) where [issuer]/[instrumentRef]
  /// get manually pinned to a specific detected account when the SMS never
  /// named one explicitly. (If it isn't a transaction at all, use
  /// setMessageCategory instead — see messageById.)
  ///
  /// Persists as an override (see DatabaseService.saveTransaction) so it's
  /// never silently re-parsed or discarded by a later cache wipe. Also pins
  /// the parent message's category as an override — even though the
  /// category value itself isn't changing — so a wipe doesn't delete the
  /// category row, fall through to re-classifying the message from
  /// scratch, and re-derive a fresh (uncorrected) transaction on top of
  /// this one.
  Future<void> updateTransaction(
    Transaction transaction, {
    required TxnDirection direction,
    required InstrumentType instrument,
    String? merchant,
    String? walletType,
    SpendCategory? spendCategory,
    String? issuer,
    String? instrumentRef,
  }) async {
    final cleanedMerchant = merchant?.trim();
    final cleanedWallet = walletType?.trim();
    final updated = Transaction(
      smsId: transaction.smsId,
      date: transaction.date,
      amount: transaction.amount,
      direction: direction,
      instrument: instrument,
      instrumentRef: instrumentRef ?? transaction.instrumentRef,
      issuer: issuer ?? transaction.issuer,
      merchant: (cleanedMerchant == null || cleanedMerchant.isEmpty) ? null : cleanedMerchant,
      balanceAfter: transaction.balanceAfter,
      entityType: transaction.entityType,
      walletType: (cleanedWallet == null || cleanedWallet.isEmpty) ? null : cleanedWallet,
      billDueDate: transaction.billDueDate,
      fastagWalletId: transaction.fastagWalletId,
      vehicleNumber: transaction.vehicleNumber,
      rawBody: transaction.rawBody,
      isOverridden: true,
      spendCategory: spendCategory,
    );

    final index = _transactions.indexWhere((t) => t.smsId == transaction.smsId);
    if (index != -1) {
      _transactions[index] = updated;
    } else {
      _transactions.add(updated);
    }
    notifyListeners();

    await _db.saveTransaction(updated, isOverride: true);
    await _db.saveCategory(transaction.smsId, SmsCategory.transactional, isOverride: true);

    final message = messageById(transaction.smsId);
    if (message != null) {
      message.category = SmsCategory.transactional;
      message.isCategoryOverridden = true;
    }

    if (await _rememberMerchantCategory(updated, spendCategory)) await _applyMerchantRulesToUncategorised();
    notifyListeners();
  }

  /// Bulk equivalent of [updateTransaction] for TransactionListScreen's
  /// multi-select "Edit" action. Unlike the single-transaction edit sheet
  /// (which always writes every field), a batch edit almost never means
  /// "set every field to this same value" — usually just one, e.g.
  /// correcting the Instrument for a batch that all landed as "Other" —
  /// so every param here is optional and only touches what's actually
  /// passed: [direction]/[instrument] left null keep each transaction's
  /// existing value, [merchant]/[walletType] left null or blank do the
  /// same (bulk-*clearing* either isn't supported — too easy to wipe a
  /// whole batch by leaving a field blank while only meaning to change
  /// something else), and [spendCategory] defaults to [keepSpendCategory]
  /// so it takes the same three-state "leave alone / clear / set" as
  /// [Transaction.copyWith] itself.
  Future<void> updateTransactionsBulk(
    List<Transaction> transactions, {
    TxnDirection? direction,
    InstrumentType? instrument,
    String? merchant,
    String? walletType,
    Object? spendCategory = keepSpendCategory,
  }) async {
    final cleanedMerchant = merchant?.trim();
    final cleanedWallet = walletType?.trim();
    final touchesSpendCategory = !identical(spendCategory, keepSpendCategory);
    var ruleChanged = false;
    for (final t in transactions) {
      final resolvedSpendCategory = touchesSpendCategory ? spendCategory as SpendCategory? : t.spendCategory;
      final updated = t.copyWith(
        direction: direction ?? t.direction,
        instrument: instrument ?? t.instrument,
        merchant: (cleanedMerchant == null || cleanedMerchant.isEmpty) ? t.merchant : cleanedMerchant,
        walletType: (cleanedWallet == null || cleanedWallet.isEmpty) ? t.walletType : cleanedWallet,
        spendCategory: resolvedSpendCategory,
        isOverridden: true,
      );
      final index = _transactions.indexWhere((x) => x.smsId == t.smsId);
      if (index != -1) _transactions[index] = updated;
      await _db.saveTransaction(updated, isOverride: true);
      await _db.saveCategory(t.smsId, SmsCategory.transactional, isOverride: true);

      final message = messageById(t.smsId);
      if (message != null) {
        message.category = SmsCategory.transactional;
        message.isCategoryOverridden = true;
      }

      if (touchesSpendCategory && await _rememberMerchantCategory(updated, resolvedSpendCategory)) {
        ruleChanged = true;
      }
    }
    if (ruleChanged) await _applyMerchantRulesToUncategorised();
    notifyListeners();
  }

  /// Detected bank/card accounts a transaction can be manually pinned to —
  /// the pick-list for [assignInstrumentToTransactions]. Only instruments
  /// with a known last-4 [InstrumentSummary.ref] qualify: assigning a
  /// transaction to another ref-less "account" wouldn't actually link it
  /// to anything more specific than it already is.
  List<InstrumentSummary> get assignableInstruments => groupByInstrument(_transactions)
      .where((s) => s.ref != null && (s.isBankAccount || s.isDebitCard || s.isCreditCard))
      .toList();

  /// Other transactions likely from the same real-world account as
  /// [source] but which TransactionParserService couldn't pin down (e.g.
  /// an NEFT debit that only names the recipient, never the user's own
  /// account) — still no instrumentRef of their own, and not already
  /// manually corrected. This is the "and similar messages" candidate set
  /// offered after assigning [source] to a detected account — see
  /// [assignInstrumentToTransactions] and AssignInstrumentSheet, which is
  /// expected to get the user's explicit acceptance before more than
  /// [source] itself is ever passed there — that review step is what makes
  /// it safe to cast a reasonably wide net here rather than requiring an
  /// exact match.
  ///
  /// Three signals, checked in order of how much they're trusted:
  /// 1. Same SMS sender address — the strongest signal, but banks route
  ///    the same alerts through several different DLT sender codes (e.g.
  ///    HDFC's own alerts can arrive as "VM-HDFCBK", "AD-HDFCBK-S", etc.
  ///    depending on operator/circle), so this alone misses a lot.
  /// 2. Same detected [Transaction.issuer] — the bank name
  ///    TransactionParserService already normalised out of the sender/body,
  ///    so it stays the same across those sender-code variants even when
  ///    the raw address doesn't match.
  /// 3. Only when *neither* transaction has a detected issuer: the same
  ///    normalised body template (see [normalizedSmsTemplate]) — banks'
  ///    alert SMS are near-identical apart from the amount/date/reference,
  ///    so two bodies that collapse to the same template are still decent
  ///    evidence of a shared sender. Gated on both issuers being null so a
  ///    generic "Rs # debited ... Avl Bal Rs #"-style template two
  ///    *different* banks happen to share can't override a real,
  ///    already-known issuer mismatch.
  List<Transaction> findSimilarUnassignedTransactions(Transaction source) {
    final sourceAddress = messageById(source.smsId)?.address;
    final sourceIssuer = source.issuer;
    final sourceTemplate = normalizedSmsTemplate(source.rawBody);

    return _transactions.where((t) {
      if (t.smsId == source.smsId) return false;
      if (t.instrumentRef != null) return false;
      if (t.isOverridden) return false;

      if (sourceAddress != null && messageById(t.smsId)?.address == sourceAddress) return true;
      if (sourceIssuer != null && t.issuer == sourceIssuer) return true;
      if (sourceIssuer == null && t.issuer == null) {
        return sourceTemplate.isNotEmpty && normalizedSmsTemplate(t.rawBody) == sourceTemplate;
      }
      return false;
    }).toList();
  }

  /// Manually pins every transaction in [transactions] to one specific
  /// detected account/card (an [assignableInstruments] entry) — for a
  /// transaction whose SMS never included an explicit account number, so
  /// TransactionParserService could tell it moved money but not through
  /// which of the user's own accounts. Marks each as overridden, same as
  /// [updateTransaction] — including pinning the parent message's category
  /// as an override too, which this used to skip: without it, a later
  /// [DatabaseService.clearAll] wipe deletes the message's still-`is_override
  /// = 0` category row even though the transaction row survived as an
  /// override, `refresh()` then finds no cached category for it and
  /// re-parses it from scratch, and that fresh, un-assigned `Transaction`
  /// silently overwrites the real one via `saveTransactionsBulk`'s `INSERT
  /// OR REPLACE` — undoing the assignment rather than "never silently
  /// un-linking it again" as intended.
  Future<void> assignInstrumentToTransactions(
    List<Transaction> transactions, {
    required InstrumentType instrument,
    required String? issuer,
    required String? instrumentRef,
  }) async {
    for (final t in transactions) {
      final updated = t.copyWith(
        instrument: instrument,
        issuer: issuer,
        instrumentRef: instrumentRef,
        isOverridden: true,
      );
      final index = _transactions.indexWhere((x) => x.smsId == t.smsId);
      if (index != -1) _transactions[index] = updated;
      await _db.saveTransaction(updated, isOverride: true);
      await _db.saveCategory(t.smsId, SmsCategory.transactional, isOverride: true);
      final message = messageById(t.smsId);
      if (message != null) {
        message.category = SmsCategory.transactional;
        message.isCategoryOverridden = true;
      }
    }
    notifyListeners();
  }

  /// User-driven correction for when TransactionParserService mis-detected
  /// [investment]'s kind, fund/scheme, AMC, or folio — the case where the
  /// message genuinely is a SIP/mutual-fund/trade confirmation, but it's
  /// filed under the wrong Invested/Redeemed tab or the wrong AMC/provider
  /// bucket. (If it isn't an investment at all, use setMessageCategory
  /// instead — see messageById.)
  ///
  /// Persists as an override (see DatabaseService.saveInvestment) so it's
  /// never silently re-parsed or discarded by a later cache wipe. Also pins
  /// the parent message's category as an override for the same reason
  /// updateTransaction does — see there.
  Future<void> updateInvestment(
    InvestmentEvent investment, {
    required InvestmentKind kind,
    String? fundOrScheme,
    String? amc,
    String? folioOrAccount,
  }) async {
    final cleanedFund = fundOrScheme?.trim();
    final cleanedAmc = amc?.trim();
    final cleanedFolio = folioOrAccount?.trim();
    final updated = InvestmentEvent(
      smsId: investment.smsId,
      date: investment.date,
      amount: investment.amount,
      kind: kind,
      rawBody: investment.rawBody,
      fundOrScheme: (cleanedFund == null || cleanedFund.isEmpty) ? null : cleanedFund,
      folioOrAccount: (cleanedFolio == null || cleanedFolio.isEmpty) ? null : cleanedFolio,
      units: investment.units,
      nav: investment.nav,
      amc: (cleanedAmc == null || cleanedAmc.isEmpty) ? null : cleanedAmc,
      isOverridden: true,
    );

    final index = _investments.indexWhere((i) => i.smsId == investment.smsId);
    if (index != -1) {
      _investments[index] = updated;
    } else {
      _investments.add(updated);
    }
    notifyListeners();

    await _db.saveInvestment(updated, isOverride: true);
    await _db.saveCategory(investment.smsId, SmsCategory.transactional, isOverride: true);

    final message = messageById(investment.smsId);
    if (message != null) {
      message.category = SmsCategory.transactional;
      message.isCategoryOverridden = true;
      notifyListeners();
    }
  }

  /// Bulk equivalent of [updateInvestment] for InvestmentListScreen's
  /// multi-select "Edit" action — same "only touches what's actually
  /// passed" design as [updateTransactionsBulk]: [kind] left null keeps
  /// each event's existing value, [fundOrScheme]/[amc]/[folioOrAccount]
  /// left null or blank do the same (bulk-*clearing* isn't supported, same
  /// reasoning as [updateTransactionsBulk] — too easy to wipe a whole batch
  /// by leaving a field blank while only meaning to change something else).
  Future<void> updateInvestmentsBulk(
    List<InvestmentEvent> investments, {
    InvestmentKind? kind,
    String? fundOrScheme,
    String? amc,
    String? folioOrAccount,
  }) async {
    final cleanedFund = fundOrScheme?.trim();
    final cleanedAmc = amc?.trim();
    final cleanedFolio = folioOrAccount?.trim();
    for (final i in investments) {
      final updated = InvestmentEvent(
        smsId: i.smsId,
        date: i.date,
        amount: i.amount,
        kind: kind ?? i.kind,
        rawBody: i.rawBody,
        fundOrScheme: (cleanedFund == null || cleanedFund.isEmpty) ? i.fundOrScheme : cleanedFund,
        folioOrAccount: (cleanedFolio == null || cleanedFolio.isEmpty) ? i.folioOrAccount : cleanedFolio,
        units: i.units,
        nav: i.nav,
        amc: (cleanedAmc == null || cleanedAmc.isEmpty) ? i.amc : cleanedAmc,
        isOverridden: true,
      );
      final index = _investments.indexWhere((x) => x.smsId == i.smsId);
      if (index != -1) _investments[index] = updated;
      await _db.saveInvestment(updated, isOverride: true);
      await _db.saveCategory(i.smsId, SmsCategory.transactional, isOverride: true);

      final message = messageById(i.smsId);
      if (message != null) {
        message.category = SmsCategory.transactional;
        message.isCategoryOverridden = true;
      }
    }
    notifyListeners();
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

    // Same idea for manually-corrected transactions — see updateTransaction.
    final autoTransactions = <Transaction>[];
    for (final t in bundle.transactions) {
      if (t.isOverridden) {
        await _db.saveTransaction(t, isOverride: true);
      } else {
        autoTransactions.add(t);
      }
    }
    if (autoTransactions.isNotEmpty) await _db.saveTransactionsBulk(autoTransactions);

    // Same idea for manually-corrected investments — see updateInvestment.
    final autoInvestments = <InvestmentEvent>[];
    for (final i in bundle.investments) {
      if (i.isOverridden) {
        await _db.saveInvestment(i, isOverride: true);
      } else {
        autoInvestments.add(i);
      }
    }
    if (autoInvestments.isNotEmpty) await _db.saveInvestmentsBulk(autoInvestments);
    notifyListeners();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }
}
