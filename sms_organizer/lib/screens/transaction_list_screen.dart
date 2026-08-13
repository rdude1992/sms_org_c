import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/duplicate_detection_service.dart';
import '../utils/formatters.dart';
import '../widgets/assign_instrument_sheet.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/search_toggle_mixin.dart';
import '../widgets/transaction_edit_sheet.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/total_stat.dart';

/// Drilldown target for Insights — shows a pre-filtered slice of
/// transactions (by direction, instrument, or month) with its own totals
/// header, rather than reproducing filter logic in every entry point.
/// Split into All/Credited/Debited tabs (swipeable, like the rest of the
/// app) so a drilldown that mixes both directions — an instrument or a
/// month — can still be narrowed down further.
class TransactionListScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Transaction> transactions;

  /// Re-applied to the live-refreshed transactions on every rebuild, on top
  /// of the id-membership check below — lets a drilldown grouped by a
  /// mutable field (spend category, instrument, merchant) drop a
  /// transaction the moment it's edited away from the group this screen
  /// represents, instead of it lingering here forever just because it was
  /// part of the original snapshot. Left null for drilldowns whose
  /// grouping can't change underneath them (a fixed date bucket) or where
  /// staying put is the intended behaviour (the Credited/Debited total
  /// cards — see the tabbed layout below, which already handles a
  /// direction change by moving the row to the right tab rather than
  /// dropping it).
  final bool Function(Transaction)? matches;

  const TransactionListScreen({
    super.key,
    required this.title,
    required this.transactions,
    this.subtitle,
    this.matches,
  });

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

enum _SortBy { dateDesc, dateAsc, valueDesc, valueAsc }

extension on _SortBy {
  String get label {
    switch (this) {
      case _SortBy.dateDesc:
        return 'Newest first';
      case _SortBy.dateAsc:
        return 'Oldest first';
      case _SortBy.valueDesc:
        return 'Highest amount';
      case _SortBy.valueAsc:
        return 'Lowest amount';
    }
  }

  int compare(Transaction a, Transaction b) {
    switch (this) {
      case _SortBy.dateDesc:
        return b.date.compareTo(a.date);
      case _SortBy.dateAsc:
        return a.date.compareTo(b.date);
      case _SortBy.valueDesc:
        return b.amount.compareTo(a.amount);
      case _SortBy.valueAsc:
        return a.amount.compareTo(b.amount);
    }
  }
}

class _TransactionListScreenState extends State<TransactionListScreen>
    with SearchToggleMixin<TransactionListScreen> {
  // Local to this screen (unlike SmsProvider.selectedIds, which the Inbox's
  // message/chat lists share) — a transaction drilldown is always opened
  // fresh from Insights, so there's no cross-screen selection state to stay
  // in sync with, and keeping it local avoids a stray selection left over
  // from a different screen bleeding in here.
  final Set<int> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  // Defaults to newest-first, matching this screen's previous fixed order.
  _SortBy _sortBy = _SortBy.dateDesc;

  /// "Expand all" — shows every tile's inline SMS-body/quick-action panel
  /// at once (see TransactionTile.expanded) instead of opening and closing
  /// the detail sheet one row at a time to check what each transaction
  /// actually says. Local, per-visit state like the Inbox's collapsible
  /// date headers and avatar-preview toggles — not worth persisting as a
  /// preference.
  bool _allExpanded = false;
  void _toggleAllExpanded() => setState(() => _allExpanded = !_allExpanded);

  /// Dense, bank-statement-style rows (date · name · colored amount,
  /// grouped under a sticky month header) — the default here since a
  /// drilldown is usually opened to scan a lot of rows at once; the toggle
  /// switches to the avatar+subtitle ListTile when a row's extra detail
  /// (instrument, spend category, "manually edited" flag, ...) is actually
  /// needed. Local/ephemeral like [_allExpanded], not worth persisting as a
  /// preference.
  bool _compact = true;
  void _toggleCompact() => setState(() => _compact = !_compact);

  /// Per-row expansion, toggled by tapping a tile's own avatar (see
  /// TransactionTile.onToggleExpand) — separate from [_allExpanded] so
  /// fixing one row doesn't require expanding (or collapsing) every other
  /// row in the list first.
  final Set<int> _expandedIds = {};
  void _toggleExpanded(int smsId) {
    setState(() {
      if (!_expandedIds.remove(smsId)) _expandedIds.add(smsId);
    });
  }

  void _toggleSelected(int smsId) {
    setState(() {
      if (!_selectedIds.remove(smsId)) _selectedIds.add(smsId);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  void _selectAll(Iterable<int> smsIds) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(smsIds);
    });
  }

  @override
  void dispose() {
    disposeSearch();
    super.dispose();
  }

  bool _matches(Transaction t, String q) {
    return (t.merchant?.toLowerCase().contains(q) ?? false) ||
        (t.issuer?.toLowerCase().contains(q) ?? false) ||
        (t.instrumentRef?.toLowerCase().contains(q) ?? false) ||
        (t.walletType?.toLowerCase().contains(q) ?? false) ||
        t.rawBody.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // [transactions] is a one-off snapshot handed down by whichever Insights
    // screen pushed this route. Re-deriving the live copy from SmsProvider
    // (matched by id, plus [widget.matches] when the caller supplied one)
    // means a correction made via a tile's "Edit transaction"/"Not a
    // transaction?" action (see TransactionTile) is reflected immediately:
    // it moves to the right Credited/Debited tab, the header totals update,
    // a message reclassified out of Transactions entirely just drops out of
    // the list, and — for a category/instrument/merchant drilldown — one
    // edited out of this particular group drops out too, all without
    // backing out and re-opening this drilldown.
    final ids = widget.transactions.map((t) => t.smsId).toSet();
    final matches = widget.matches;
    final live = context
        .watch<SmsProvider>()
        .transactions
        .where((t) => ids.contains(t.smsId) && (matches == null || matches(t)))
        .toList();

    final trimmedQuery = query.trim().toLowerCase();
    final searched = trimmedQuery.isEmpty ? live : live.where((t) => _matches(t, trimmedQuery)).toList();

    final sorted = [...searched]..sort(_sortBy.compare);
    final credited = sorted.where((t) => t.direction == TxnDirection.credit).toList();
    final debited = sorted.where((t) => t.direction == TxnDirection.debit).toList();
    // Rows for both halves of a duplicate-alert pair (see
    // duplicate_detection_service.dart) stay visible — the user still
    // received both SMS — but only one counts toward the header totals, so
    // a linked debit-card+bank-account purchase reported twice doesn't
    // double its own sum here.
    final duplicateIds = findDuplicateTransactionIds(sorted);
    final creditTotal = credited
        .where((t) => !duplicateIds.contains(t.smsId))
        .fold<double>(0, (a, t) => a + t.amount);
    final debitTotal = debited
        .where((t) => !duplicateIds.contains(t.smsId))
        .fold<double>(0, (a, t) => a + t.amount);

    // A list where every transaction shares one direction — e.g. opened via
    // the Insights "Credited"/"Debited" total card, or (the common case) a
    // merchant/instrument that's purely spend or purely income — makes the
    // All/Credited/Debited tabs pointless: one tab is empty and the other is
    // identical to "All". Skip the tab bar entirely rather than show two
    // dead tabs. An empty list falls through to the tabbed branch too (its
    // EmptyState looks the same either way).
    final isPureCredit = sorted.isNotEmpty && credited.length == sorted.length;
    final isPureDebit = sorted.isNotEmpty && debited.length == sorted.length;
    final showTabs = !isPureCredit && !isPureDebit;

    final emptyTitle = trimmedQuery.isEmpty ? 'No transactions in this range' : 'No matches for "$trimmedQuery"';

    // "Select all" is scoped to [sorted] — every transaction in this
    // drilldown regardless of which All/Credited/Debited tab happens to be
    // showing — rather than tracking the active tab just for this button;
    // ids selected from another tab still apply correctly to the bulk
    // action, they just won't show a checked tile until you swipe to them.
    final allSelected = sorted.isNotEmpty && sorted.every((t) => _selectedIds.contains(t.smsId));
    // The actual Transaction objects behind [_selectedIds] — bulk actions
    // below (edit, assign to account) need the full objects, not just ids.
    final selectedTransactions = sorted.where((t) => _selectedIds.contains(t.smsId)).toList();

    final appBarLeading =
        _selecting ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection) : null;
    final appBarTitle = _selecting
        ? Text('${_selectedIds.length} selected')
        : searchAppBarTitle(widget.title, hintText: 'Search transactions');
    final appBarActions = _selecting
        ? [
            IconButton(
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              tooltip: allSelected ? 'Select none' : 'Select all',
              onPressed: allSelected ? _clearSelection : () => _selectAll(sorted.map((t) => t.smsId)),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => showBulkTransactionEditSheet(
                context,
                context.read<SmsProvider>(),
                selectedTransactions,
                onApplied: _clearSelection,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_outlined),
              tooltip: 'Assign to account',
              onPressed: () => showAssignInstrumentSheet(
                context,
                context.read<SmsProvider>(),
                selectedTransactions,
                onApplied: _clearSelection,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'Set category',
              onPressed: () => showBulkSpendCategorySheet(
                context,
                context.read<SmsProvider>(),
                _selectedIds.toList(),
                onApplied: _clearSelection,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Not a transaction?',
              onPressed: () => showBulkCategoryPickerSheet(
                context,
                selectedCount: _selectedIds.length,
                itemLabel: 'transaction',
                onSelect: (category) {
                  context.read<SmsProvider>().setCategoryForTransactions(_selectedIds.toList(), category);
                  _clearSelection();
                },
              ),
            ),
          ]
        : [
            PopupMenuButton<_SortBy>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort by',
              initialValue: _sortBy,
              onSelected: (value) => setState(() => _sortBy = value),
              itemBuilder: (context) => [
                for (final option in _SortBy.values)
                  PopupMenuItem(
                    value: option,
                    child: Row(
                      children: [
                        if (option == _sortBy)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(option.label),
                      ],
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: Icon(_compact ? Icons.view_agenda_outlined : Icons.table_rows_outlined),
              tooltip: _compact ? 'Detailed view' : 'Compact view',
              onPressed: _toggleCompact,
            ),
            if (!_compact)
              IconButton(
                icon: Icon(_allExpanded ? Icons.unfold_less : Icons.unfold_more),
                tooltip: _allExpanded ? 'Collapse all' : 'Expand all',
                onPressed: _toggleAllExpanded,
              ),
            ...searchAppBarActions(),
          ];

    final totalsHeader = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: scheme.surfaceVariant.withOpacity(0.4),
      child: Row(
        children: [
          Expanded(
            child: TotalStat(label: 'Credited', value: creditTotal, color: const Color(0xFF10B981)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TotalStat(label: 'Debited', value: debitTotal, color: const Color(0xFFEF4444)),
          ),
          Text(
            '${sorted.length} txns',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    if (!showTabs) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarLeading,
          title: appBarTitle,
          actions: appBarActions,
          bottom: _selecting || isSearching || widget.subtitle == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.subtitle!,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                ),
        ),
        body: Column(
          children: [
            totalsHeader,
            Expanded(
              child: _TransactionListView(
                transactions: sorted,
                emptyText: emptyTitle,
                selectedIds: _selectedIds,
                selecting: _selecting,
                onToggleSelected: _toggleSelected,
                allExpanded: _allExpanded,
                expandedIds: _expandedIds,
                onToggleExpanded: _toggleExpanded,
                compact: _compact,
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: appBarLeading,
          title: appBarTitle,
          actions: appBarActions,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(isSearching || widget.subtitle == null ? 48 : 68),
            child: Column(
              children: [
                if (!isSearching && widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.subtitle!,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                TabBar(
                  tabs: [
                    Tab(text: 'All (${sorted.length})'),
                    Tab(text: 'Credited (${credited.length})'),
                    Tab(text: 'Debited (${debited.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? EmptyState(
                icon: trimmedQuery.isEmpty ? Icons.receipt_long_outlined : Icons.search_off_outlined,
                title: emptyTitle,
              )
            : Column(
                children: [
                  totalsHeader,
                  Expanded(
                    child: TabBarView(
                      children: [
                        _TransactionListView(
                          transactions: sorted,
                          emptyText: emptyTitle,
                          selectedIds: _selectedIds,
                          selecting: _selecting,
                          onToggleSelected: _toggleSelected,
                          allExpanded: _allExpanded,
                          expandedIds: _expandedIds,
                          onToggleExpanded: _toggleExpanded,
                          compact: _compact,
                        ),
                        _TransactionListView(
                          transactions: credited,
                          emptyText: 'No credited transactions.',
                          selectedIds: _selectedIds,
                          selecting: _selecting,
                          onToggleSelected: _toggleSelected,
                          allExpanded: _allExpanded,
                          expandedIds: _expandedIds,
                          onToggleExpanded: _toggleExpanded,
                          compact: _compact,
                        ),
                        _TransactionListView(
                          transactions: debited,
                          emptyText: 'No debited transactions.',
                          selectedIds: _selectedIds,
                          selecting: _selecting,
                          onToggleSelected: _toggleSelected,
                          allExpanded: _allExpanded,
                          expandedIds: _expandedIds,
                          onToggleExpanded: _toggleExpanded,
                          compact: _compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TransactionListView extends StatelessWidget {
  final List<Transaction> transactions;
  final String emptyText;
  final Set<int> selectedIds;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;
  final bool allExpanded;
  final Set<int> expandedIds;
  final ValueChanged<int> onToggleExpanded;
  final bool compact;

  const _TransactionListView({
    required this.transactions,
    required this.emptyText,
    required this.selectedIds,
    required this.selecting,
    required this.onToggleSelected,
    required this.allExpanded,
    required this.expandedIds,
    required this.onToggleExpanded,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return EmptyState(icon: Icons.receipt_long_outlined, title: emptyText);
    }
    // [transactions] is re-derived from SmsProvider on every rebuild (see
    // TransactionListScreen.build), so a pull-triggered refresh() naturally
    // flows through to this list the same way it already does for the
    // Inbox/Insights lists — no separate reload needed here.
    return RefreshIndicator(
      onRefresh: context.read<SmsProvider>().refresh,
      child: compact ? _buildCompact(context) : _buildDetailed(context),
    );
  }

  Widget _buildDetailed(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        return TransactionTile(
          transaction: t,
          selected: selectedIds.contains(t.smsId),
          selectionMode: selecting,
          onTap: selecting ? () => onToggleSelected(t.smsId) : null,
          onLongPress: selecting ? () => onToggleSelected(t.smsId) : null,
          onSelectStart: () => onToggleSelected(t.smsId),
          expanded: allExpanded || expandedIds.contains(t.smsId),
          onToggleExpand: selecting ? null : () => onToggleExpanded(t.smsId),
        );
      },
    );
  }

  /// Month-grouped header rendering of [TransactionTile.compact] — mirrors
  /// the Inbox's day-header list (see _StickyMessageList in
  /// inbox_screen.dart), just grouped by month instead of by day since a
  /// bank-statement-style scan benefits from coarser sections. Assumes
  /// [transactions] is already contiguous by month, which holds for the
  /// screen's date-based sort orders (newest/oldest first); under a
  /// value-based sort the same month can recur in more than one group —
  /// a cosmetic quirk, not a correctness issue, since every transaction
  /// still appears exactly once.
  Widget _buildCompact(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groupTransactionsByMonth(transactions);
    final slivers = <Widget>[
      for (final group in groups) ...[
        SliverPersistentHeader(
          pinned: false,
          delegate: _MonthHeaderDelegate(label: Formatters.monthYear(group.month)),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final t = group.items[index];
              return Column(
                children: [
                  TransactionTile(
                    transaction: t,
                    compact: true,
                    selected: selectedIds.contains(t.smsId),
                    selectionMode: selecting,
                    onTap: selecting ? () => onToggleSelected(t.smsId) : null,
                    onLongPress: selecting ? () => onToggleSelected(t.smsId) : null,
                    onSelectStart: () => onToggleSelected(t.smsId),
                  ),
                  Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withOpacity(0.4)),
                ],
              );
            },
            childCount: group.items.length,
          ),
        ),
      ],
    ];
    return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: slivers);
  }
}

class _MonthGroup {
  final DateTime month;
  final List<Transaction> items;
  _MonthGroup(this.month, this.items);
}

List<_MonthGroup> _groupTransactionsByMonth(List<Transaction> transactions) {
  final groups = <_MonthGroup>[];
  for (final t in transactions) {
    if (groups.isNotEmpty && groups.last.month.year == t.date.year && groups.last.month.month == t.date.month) {
      groups.last.items.add(t);
    } else {
      groups.add(_MonthGroup(DateTime(t.date.year, t.date.month), [t]));
    }
  }
  return groups;
}

class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  const _MonthHeaderDelegate({required this.label});

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MonthHeaderDelegate oldDelegate) => oldDelegate.label != label;
}
