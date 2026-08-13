import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transaction.dart';
import '../providers/sms_provider.dart';
import '../services/holdings_service.dart';
import '../services/insights_service.dart';
import '../utils/formatters.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/investment_edit_sheet.dart';
import '../widgets/investment_tile.dart';
import '../widgets/search_toggle_mixin.dart';
import '../widgets/ui/breakdown_donut.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/filter_chip_bar.dart';
import '../widgets/ui/gain_loss_stat.dart';
import '../widgets/ui/total_stat.dart';
import '../widgets/ui/trend_bar_chart.dart';
import '../widgets/ui/trend_line_chart.dart';
import 'amc_detail_screen.dart';

/// Sort options for the Invested/Redeemed/All tabs — mirrors
/// TransactionListScreen's `_SortBy`.
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

  int compare(InvestmentEvent a, InvestmentEvent b) {
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

/// How far back the "By AMC" tab's donut/trend chart look — independent of
/// whatever range brought the caller into this screen, so someone drilled
/// into a single provider's own investments (see [_ProviderRow]'s onTap)
/// can still slice that provider's history by time.
enum InvestmentRange { thisMonth, last3Months, last6Months, thisYear, allTime }

/// Named (unlike most of this file's other extensions) specifically so
/// AmcDetailScreen — a separate library — can rely on plainly importing
/// this file to bring these members into scope, the same way
/// [InvestmentKindX] in transaction.dart is named for its own out-of-file
/// callers.
extension InvestmentRangeX on InvestmentRange {
  String get label {
    switch (this) {
      case InvestmentRange.thisMonth:
        return 'This month';
      case InvestmentRange.last3Months:
        return 'Last 3 months';
      case InvestmentRange.last6Months:
        return 'Last 6 months';
      case InvestmentRange.thisYear:
        return 'This year';
      case InvestmentRange.allTime:
        return 'All time';
    }
  }

  /// The (from, to) window this range covers, as of [now]. `allTime` has no
  /// bound on either end.
  (DateTime?, DateTime?) boundsFrom(DateTime now) {
    switch (this) {
      case InvestmentRange.thisMonth:
        return (DateTime(now.year, now.month, 1), now);
      case InvestmentRange.last3Months:
        return (DateTime(now.year, now.month - 2, 1), now);
      case InvestmentRange.last6Months:
        return (DateTime(now.year, now.month - 5, 1), now);
      case InvestmentRange.thisYear:
        return (DateTime(now.year, 1, 1), now);
      case InvestmentRange.allTime:
        return (null, null);
    }
  }

  /// How finely the trend chart should bucket this range — see
  /// InsightsRange.trendGranularity for the same idea applied to
  /// transactions.
  TrendGranularity get trendGranularity {
    switch (this) {
      case InvestmentRange.thisMonth:
        return TrendGranularity.day;
      case InvestmentRange.last3Months:
        return TrendGranularity.week;
      case InvestmentRange.last6Months:
      case InvestmentRange.thisYear:
      case InvestmentRange.allTime:
        return TrendGranularity.month;
    }
  }
}

/// Drilldown target for the Insights "Investments" card — mirrors
/// TransactionListScreen's All/split-direction tab pattern, split here into
/// By AMC/Invested/Redeemed/All since that's the distinction InvestmentKind
/// draws. "By AMC" — which groups events by AMC/broker (see
/// [InvestmentEvent.providerGroupKey]) and carries its own donut/trend
/// analytics — leads since it's the most useful breakdown; the flat "All"
/// list is closer to a raw data dump, so it's last.
class InvestmentListScreen extends StatefulWidget {
  final String? subtitle;
  final List<InvestmentEvent> investments;

  /// The true, unscoped superset [investments] was drawn from — e.g. every
  /// investment ever detected, when [investments] is only this month's. The
  /// "By AMC" tab's own date-range picker filters from this instead of
  /// [investments], so picking a wider window there always has an effect
  /// instead of silently being a no-op against an already-narrowed list (see
  /// _AmcAnalytics). Defaults to [investments] itself when omitted — correct
  /// for a drilldown that's already maximally specific (e.g. one provider's
  /// events), where there's no broader superset to offer.
  final List<InvestmentEvent>? allInvestments;

  /// Which tab opens first — defaults to 0 ("By AMC"), the most useful
  /// breakdown when there's more than one provider to break down. A
  /// single-provider drilldown (see [_ProviderRow]'s onTap) passes 3
  /// ("All") instead: "By AMC" would just show that one provider again,
  /// a redundant landing tab. The tab itself is still there either way —
  /// its own range picker/trend chart are still useful for one provider —
  /// just not what opens by default.
  final int initialTabIndex;

  const InvestmentListScreen({
    super.key,
    required this.investments,
    this.allInvestments,
    this.subtitle,
    this.initialTabIndex = 0,
  });

  @override
  State<InvestmentListScreen> createState() => _InvestmentListScreenState();
}

class _InvestmentListScreenState extends State<InvestmentListScreen>
    with SearchToggleMixin<InvestmentListScreen> {
  // Local to this screen (mirrors TransactionListScreen's own local
  // selection) — an investment drilldown is always opened fresh from
  // Insights, so there's no cross-screen selection state to stay in sync
  // with. Shared across the Invested/Redeemed/All tabs (not "By AMC", which
  // renders provider summary rows rather than individual InvestmentTiles).
  final Set<int> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  _SortBy _sortBy = _SortBy.dateDesc;

  bool _allExpanded = false;
  void _toggleAllExpanded() => setState(() => _allExpanded = !_allExpanded);

  bool _compact = true;
  void _toggleCompact() => setState(() => _compact = !_compact);

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

  bool _matches(InvestmentEvent i, String q) {
    return (i.fundOrScheme?.toLowerCase().contains(q) ?? false) ||
        (i.amc?.toLowerCase().contains(q) ?? false) ||
        (i.folioOrAccount?.toLowerCase().contains(q) ?? false) ||
        i.rawBody.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Both [investments] and [allInvestments] are one-off snapshots handed
    // down at navigation time; re-deriving live copies from SmsProvider
    // (matched by id) means this screen keeps reflecting reality rather than
    // going stale the moment something changes elsewhere in the app.
    final providerInvestments = context.watch<SmsProvider>().investments;
    final scopedIds = widget.investments.map((i) => i.smsId).toSet();
    final liveInvestmentsUnfiltered =
        providerInvestments.where((i) => scopedIds.contains(i.smsId)).toList();
    final fullIds = (widget.allInvestments ?? widget.investments).map((i) => i.smsId).toSet();
    final liveAllInvestmentsUnfiltered =
        providerInvestments.where((i) => fullIds.contains(i.smsId)).toList();

    // A search query narrows the whole screen's universe, including the "By
    // AMC" tab's own range-filtered view — not just the flat 3 tabs — so
    // every tab stays consistent with what's in the search box.
    final trimmedQuery = query.trim().toLowerCase();
    final liveInvestments = trimmedQuery.isEmpty
        ? liveInvestmentsUnfiltered
        : liveInvestmentsUnfiltered.where((i) => _matches(i, trimmedQuery)).toList();
    final liveAllInvestments = trimmedQuery.isEmpty
        ? liveAllInvestmentsUnfiltered
        : liveAllInvestmentsUnfiltered.where((i) => _matches(i, trimmedQuery)).toList();

    final sorted = [...liveInvestments]..sort(_sortBy.compare);
    // A value statement (InvestmentKind.valuationUpdate) states what a
    // holding is worth, not money moving in or out, so it belongs in
    // neither the Invested nor Redeemed tab — only "All".
    final invested = sorted.where((i) => !i.kind.isRedemption && !i.kind.isValuationOnly).toList();
    final redeemed = sorted.where((i) => i.kind.isRedemption).toList();
    final investedTotal = invested.fold<double>(0, (a, i) => a + i.amount);
    final redeemedTotal = redeemed.fold<double>(0, (a, i) => a + i.amount);
    final providers = _groupByProvider(sorted);

    // "Select all" is scoped to [sorted] — every investment across the
    // Invested/Redeemed/All tabs regardless of which one happens to be
    // showing — rather than tracking the active tab just for this button.
    final allSelected = sorted.isNotEmpty && sorted.every((i) => _selectedIds.contains(i.smsId));
    final selectedInvestments = sorted.where((i) => _selectedIds.contains(i.smsId)).toList();

    final appBarLeading =
        _selecting ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection) : null;
    final appBarTitle = _selecting
        ? Text('${_selectedIds.length} selected')
        : searchAppBarTitle('Investments', hintText: 'Search investments');
    final appBarActions = _selecting
        ? [
            IconButton(
              icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
              tooltip: allSelected ? 'Select none' : 'Select all',
              onPressed: allSelected ? _clearSelection : () => _selectAll(sorted.map((i) => i.smsId)),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => showBulkInvestmentEditSheet(
                context,
                context.read<SmsProvider>(),
                selectedInvestments,
                onApplied: _clearSelection,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'Not an investment?',
              onPressed: () => showBulkCategoryPickerSheet(
                context,
                selectedCount: _selectedIds.length,
                itemLabel: 'investment',
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

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          leading: appBarLeading,
          title: appBarTitle,
          actions: appBarActions,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(isSearching || widget.subtitle == null ? 48 : 68),
            child: Column(
              children: [
                if (!_selecting && !isSearching && widget.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.subtitle!,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'By AMC (${providers.length})'),
                    Tab(text: 'Invested (${invested.length})'),
                    Tab(text: 'Redeemed (${redeemed.length})'),
                    Tab(text: 'All (${sorted.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? EmptyState(
                icon: trimmedQuery.isEmpty ? Icons.trending_up : Icons.search_off_outlined,
                title: trimmedQuery.isEmpty
                    ? 'No investment activity in this range'
                    : 'No matches for "$trimmedQuery"',
              )
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: scheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TotalStat(label: 'Invested', value: investedTotal, color: scheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TotalStat(
                              label: 'Redeemed', value: redeemedTotal, color: const Color(0xFFF59E0B)),
                        ),
                        // Builder gives us a context below DefaultTabController
                        // (the outer `context` here is this widget's own,
                        // which sits above it in the tree we're building) so
                        // DefaultTabController.of can actually find it.
                        Builder(
                          builder: (context) => InkWell(
                            borderRadius: BorderRadius.circular(6),
                            // Index 3 is the "All" tab — see the TabBar above.
                            onTap: () => DefaultTabController.of(context).animateTo(3),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                '${sorted.length} events',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  decoration: TextDecoration.underline,
                                  decorationColor: scheme.onSurfaceVariant.withOpacity(0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _AmcListView(providers: providers, allInvestments: liveAllInvestments),
                        _InvestmentListView(
                          investments: invested,
                          emptyText: 'Nothing invested.',
                          selectedIds: _selectedIds,
                          selecting: _selecting,
                          onToggleSelected: _toggleSelected,
                          allExpanded: _allExpanded,
                          expandedIds: _expandedIds,
                          onToggleExpanded: _toggleExpanded,
                          compact: _compact,
                        ),
                        _InvestmentListView(
                          investments: redeemed,
                          emptyText: 'Nothing redeemed.',
                          selectedIds: _selectedIds,
                          selecting: _selecting,
                          onToggleSelected: _toggleSelected,
                          allExpanded: _allExpanded,
                          expandedIds: _expandedIds,
                          onToggleExpanded: _toggleExpanded,
                          compact: _compact,
                        ),
                        _InvestmentListView(
                          investments: sorted,
                          emptyText: 'No investment activity.',
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

class _InvestmentListView extends StatelessWidget {
  final List<InvestmentEvent> investments;
  final String emptyText;
  final Set<int> selectedIds;
  final bool selecting;
  final ValueChanged<int> onToggleSelected;
  final bool allExpanded;
  final Set<int> expandedIds;
  final ValueChanged<int> onToggleExpanded;
  final bool compact;

  const _InvestmentListView({
    required this.investments,
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
    if (investments.isEmpty) {
      return EmptyState(icon: Icons.trending_up, title: emptyText);
    }
    // [investments] is re-derived from SmsProvider on every rebuild (see
    // InvestmentListScreen.build), so a pull-triggered refresh() naturally
    // flows through to this list — mirrors TransactionListScreen's
    // _TransactionListView.
    return RefreshIndicator(
      onRefresh: context.read<SmsProvider>().refresh,
      child: compact ? _buildCompact(context) : _buildDetailed(context),
    );
  }

  Widget _buildDetailed(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: investments.length,
      itemBuilder: (context, index) {
        final i = investments[index];
        return InvestmentTile(
          investment: i,
          selected: selectedIds.contains(i.smsId),
          selectionMode: selecting,
          onTap: selecting ? () => onToggleSelected(i.smsId) : null,
          onLongPress: selecting ? () => onToggleSelected(i.smsId) : null,
          onSelectStart: () => onToggleSelected(i.smsId),
          expanded: allExpanded || expandedIds.contains(i.smsId),
          onToggleExpand: selecting ? null : () => onToggleExpanded(i.smsId),
        );
      },
    );
  }

  /// Month-grouped header rendering of [InvestmentTile.compact] — mirrors
  /// TransactionListScreen's _buildCompact. Assumes [investments] is already
  /// contiguous by month, which holds for the screen's date-based sort
  /// orders; under a value-based sort the same month can recur in more than
  /// one group — a cosmetic quirk, not a correctness issue, since every
  /// investment still appears exactly once.
  Widget _buildCompact(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = _groupInvestmentsByMonth(investments);
    final slivers = <Widget>[
      for (final group in groups) ...[
        SliverPersistentHeader(
          pinned: false,
          delegate: _InvestmentMonthHeaderDelegate(label: Formatters.monthYear(group.month)),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final i = group.items[index];
              return Column(
                children: [
                  InvestmentTile(
                    investment: i,
                    compact: true,
                    selected: selectedIds.contains(i.smsId),
                    selectionMode: selecting,
                    onTap: selecting ? () => onToggleSelected(i.smsId) : null,
                    onLongPress: selecting ? () => onToggleSelected(i.smsId) : null,
                    onSelectStart: () => onToggleSelected(i.smsId),
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

class _InvestmentMonthGroup {
  final DateTime month;
  final List<InvestmentEvent> items;
  _InvestmentMonthGroup(this.month, this.items);
}

List<_InvestmentMonthGroup> _groupInvestmentsByMonth(List<InvestmentEvent> investments) {
  final groups = <_InvestmentMonthGroup>[];
  for (final i in investments) {
    if (groups.isNotEmpty && groups.last.month.year == i.date.year && groups.last.month.month == i.date.month) {
      groups.last.items.add(i);
    } else {
      groups.add(_InvestmentMonthGroup(DateTime(i.date.year, i.date.month), [i]));
    }
  }
  return groups;
}

class _InvestmentMonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  const _InvestmentMonthHeaderDelegate({required this.label});

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
  bool shouldRebuild(covariant _InvestmentMonthHeaderDelegate oldDelegate) => oldDelegate.label != label;
}

/// One row per AMC/broker (see [InvestmentEvent.providerGroupKey]) —
/// e.g. "Axis MF", "Zerodha", "NPS" — with invested/redeemed totals and
/// the events feeding it, for the "By AMC" tab.
class _ProviderSummary {
  final String key;
  final String name;
  double invested = 0;
  double redeemed = 0;
  final List<InvestmentEvent> events = [];

  _ProviderSummary({required this.key, required this.name});

  int get count => events.length;
  double get total => invested + redeemed;
}

List<_ProviderSummary> _groupByProvider(List<InvestmentEvent> investments) {
  final map = <String, _ProviderSummary>{};
  for (final i in investments) {
    final summary = map.putIfAbsent(
      i.providerGroupKey,
      () => _ProviderSummary(key: i.providerGroupKey, name: i.providerDisplayName),
    );
    // A value statement contributes to neither bucket (see
    // InvestmentKind.isValuationOnly) — it still joins [summary.events] so
    // it's visible when drilling into this provider's raw list, it just
    // shouldn't inflate the donut/total by double-counting a stated worth
    // on top of the actual cash flows that produced it.
    if (!i.kind.isValuationOnly) {
      if (i.kind.isRedemption) {
        summary.redeemed += i.amount;
      } else {
        summary.invested += i.amount;
      }
    }
    summary.events.add(i);
  }
  return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

/// The "By AMC" tab: a self-contained analytics header — its own time
/// range filter driving a by-provider donut, an invested/redeemed trend
/// chart, and the provider rows below — so picking e.g. "This month" shows
/// only that month's events, counts and totals throughout the whole tab.
class _AmcListView extends StatefulWidget {
  /// Only used for the empty-state guard below — reflects whatever scope
  /// the caller opened this screen with, same as the other 3 tabs.
  final List<_ProviderSummary> providers;

  /// The true unscoped dataset (see InvestmentListScreen.allInvestments) —
  /// everything the range picker and its drilldowns filter from.
  final List<InvestmentEvent> allInvestments;

  const _AmcListView({required this.providers, required this.allInvestments});

  @override
  State<_AmcListView> createState() => _AmcListViewState();
}

class _AmcListViewState extends State<_AmcListView> {
  InvestmentRange _range = InvestmentRange.allTime;

  @override
  Widget build(BuildContext context) {
    if (widget.providers.isEmpty) {
      return const EmptyState(icon: Icons.trending_up, title: 'No investment activity.');
    }

    final now = DateTime.now();
    final (from, to) = _range.boundsFrom(now);
    final filteredInvestments = widget.allInvestments.where((i) {
      if (from != null && i.date.isBefore(from)) return false;
      if (to != null && i.date.isAfter(to)) return false;
      return true;
    }).toList();
    final filteredProviders = _groupByProvider(filteredInvestments);

    return ListView(
      children: [
        _AmcAnalytics(
          range: _range,
          onRangeSelected: (r) => setState(() => _range = r),
          allInvestments: widget.allInvestments,
        ),
        for (final p in filteredProviders)
          _ProviderRow(provider: p, allInvestments: widget.allInvestments),
      ],
    );
  }
}

/// Range filter + by-provider donut + invested/redeemed trend chart for
/// the "By AMC" tab — filters [allInvestments] by [range] internally rather
/// than taking an already-filtered list, so it can offer finer/coarser
/// windows than whatever range the caller filtered this whole screen to
/// (see InvestmentListScreen.allInvestments for why that requires the true
/// unscoped dataset, not whatever this screen's other 3 tabs are showing).
class _AmcAnalytics extends StatelessWidget {
  final InvestmentRange range;
  final ValueChanged<InvestmentRange> onRangeSelected;
  final List<InvestmentEvent> allInvestments;

  const _AmcAnalytics({
    required this.range,
    required this.onRangeSelected,
    required this.allInvestments,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final (from, to) = range.boundsFrom(now);
    final filtered = allInvestments.where((i) {
      if (from != null && i.date.isBefore(from)) return false;
      if (to != null && i.date.isAfter(to)) return false;
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipBar<InvestmentRange>(
            values: InvestmentRange.values,
            selected: range,
            labelBuilder: (r) => r.label,
            onSelected: onRangeSelected,
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No investment activity in this range.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ..._buildCharts(context, filtered, from, to),
        ],
      ),
    );
  }

  List<Widget> _buildCharts(
    BuildContext context,
    List<InvestmentEvent> filtered,
    DateTime? from,
    DateTime? to,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final providers = _groupByProvider(filtered);
    final topProviders = providers.take(6).toList();
    final otherProvidersTotal = providers.skip(6).fold<double>(0, (a, p) => a + p.total);

    void openProvider(String key) {
      final match = providers.firstWhere((p) => p.key == key);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AmcDetailScreen(
            providerKey: match.key,
            providerName: match.name,
            allInvestments: allInvestments,
          ),
        ),
      );
    }

    // Bucketed invested/redeemed totals for the trend chart — same
    // granularity-by-range approach Insights uses for transactions (see
    // InsightsRange.trendGranularity), just applied to investment events.
    final buckets = <String, ({DateTime date, double invested, double redeemed})>{};
    for (final i in filtered) {
      if (i.kind.isValuationOnly) continue; // a stated worth, not a cash flow — see isValuationOnly
      final bucketStart = trendBucketStart(i.date, range.trendGranularity);
      final key = bucketStart.toIso8601String();
      final existing = buckets[key];
      final newInvested = (existing?.invested ?? 0) + (i.kind.isRedemption ? 0 : i.amount);
      final newRedeemed = (existing?.redeemed ?? 0) + (i.kind.isRedemption ? i.amount : 0);
      buckets[key] = (date: bucketStart, invested: newInvested, redeemed: newRedeemed);
    }
    // Zero-fill gaps (see bucketStartsBetween) so a month/week/day with no
    // investment activity still gets a visible zero bar instead of just
    // vanishing from between its neighbours — same fix as the transactions
    // trend chart in InsightsService.build.
    final rawPoints = buckets.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final List<({DateTime date, double invested, double redeemed})> points;
    if (rawPoints.isEmpty) {
      points = [];
    } else {
      final rangeStart = from ?? rawPoints.first.date;
      final rangeEnd = to ?? rawPoints.last.date;
      final byDate = {for (final p in rawPoints) p.date: p};
      points = [
        for (final d in bucketStartsBetween(rangeStart, rangeEnd, range.trendGranularity))
          byDate[d] ?? (date: d, invested: 0.0, redeemed: 0.0),
      ];
    }

    void openBucket(DateTime bucketStart) {
      late final String title;
      late final bool Function(InvestmentEvent) matchesBucket;
      switch (range.trendGranularity) {
        case TrendGranularity.day:
          title = Formatters.dayMonthYear(bucketStart);
          matchesBucket = (i) => Formatters.isSameDay(i.date, bucketStart);
          break;
        case TrendGranularity.week:
          final weekEnd = DateTime(bucketStart.year, bucketStart.month, bucketStart.day + 6, 23, 59, 59);
          title = 'Week of ${Formatters.dayMonth(bucketStart)}';
          matchesBucket = (i) => !i.date.isBefore(bucketStart) && !i.date.isAfter(weekEnd);
          break;
        case TrendGranularity.month:
          title = Formatters.monthYear(bucketStart);
          matchesBucket = (i) => i.date.year == bucketStart.year && i.date.month == bucketStart.month;
          break;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvestmentListScreen(
            investments: filtered.where(matchesBucket).toList(),
            allInvestments: allInvestments,
            subtitle: title,
          ),
        ),
      );
    }

    // Holdings are reconstructed from the true unscoped dataset (not
    // [filtered]) so units-held/current-value reflect the real current
    // position regardless of which range chip is selected above — the range
    // only zooms the value trend chart's x-axis window, same as
    // AmcDetailScreen. See holdings_service.dart.
    final holdings = computeFundHoldings(allInvestments);
    final totalInvested = holdings.fold<double>(0, (a, h) => a + h.netInvested);
    final totalValue = holdings.fold<double>(0, (a, h) => a + h.estimatedValue);
    final totalGain = totalValue - totalInvested;
    final totalGainPct = totalInvested <= 0 ? null : (totalGain / totalInvested) * 100;
    final valueTrend = buildValueTrend(holdings, range.trendGranularity, from, to);

    String valueAxisLabel(DateTime date) {
      switch (range.trendGranularity) {
        case TrendGranularity.day:
          return Formatters.dayOnly(date);
        case TrendGranularity.week:
          return Formatters.dayMonth(date);
        case TrendGranularity.month:
          // Stacked on two lines (TrendLineChart renders the embedded
          // newline as such) rather than "Aug 25" on one — see
          // Formatters.monthOnly.
          return '${Formatters.monthOnly(date)}\n${Formatters.yearOnlyShort(date)}';
      }
    }

    String valueTooltipLabel(DateTime date) {
      switch (range.trendGranularity) {
        case TrendGranularity.day:
          return Formatters.dayOnly(date);
        case TrendGranularity.week:
          return Formatters.dayMonth(date);
        case TrendGranularity.month:
          return Formatters.monthYear(date);
      }
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: BreakdownDonut(
          labels: [for (final p in topProviders) p.name, if (otherProvidersTotal > 0) 'Other'],
          keys: [for (final p in topProviders) p.key, if (otherProvidersTotal > 0) null],
          values: [
            for (final p in topProviders) p.total,
            if (otherProvidersTotal > 0) otherProvidersTotal,
          ],
          onTapKey: openProvider,
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TrendBarChart(
          dates: [for (final p in points) p.date],
          primaryValues: [for (final p in points) p.invested],
          secondaryValues: [for (final p in points) p.redeemed],
          granularity: range.trendGranularity,
          primaryLabel: 'Invested',
          secondaryLabel: 'Redeemed',
          primaryColor: scheme.primary,
          secondaryColor: const Color(0xFFF59E0B),
          onTapBucket: openBucket,
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: TotalStat(label: 'Invested', value: totalInvested, color: scheme.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: TotalStat(label: 'Est. current value', value: totalValue, color: scheme.onSurface),
            ),
            const SizedBox(width: 12),
            Expanded(child: GainLossStat(gain: totalGain, gainPct: totalGainPct)),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child:
            Text(kInvestmentEstimateNote, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TrendLineChart(
          dates: [for (final p in valueTrend) p.date],
          series: [
            TrendLineSeries(
              label: 'Invested',
              color: scheme.primary,
              values: [for (final p in valueTrend) p.invested],
            ),
            TrendLineSeries(
              label: 'Est. value',
              color: kGainColor,
              values: [for (final p in valueTrend) p.value],
            ),
          ],
          axisLabelBuilder: valueAxisLabel,
          tooltipDateBuilder: valueTooltipLabel,
          valueFormatter: Formatters.currency,
          axisValueFormatter: Formatters.compactCurrency,
        ),
      ),
      const SizedBox(height: 8),
    ];
  }
}

class _ProviderRow extends StatelessWidget {
  final _ProviderSummary provider;

  /// Passed straight through to the pushed screen (see
  /// InvestmentListScreen.allInvestments) so its "By AMC" tab keeps access
  /// to the true unscoped dataset rather than being narrowed a level
  /// further every time a provider row is drilled into.
  final List<InvestmentEvent> allInvestments;

  const _ProviderRow({required this.provider, required this.allInvestments});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final p = provider;
    // A raw Row in a Padding (like TransactionTile's `compact` mode /
    // Insights' SpendCategoryRow), not a ListTile — ListTile enforces a
    // minimum row height even with contentPadding/minVerticalPadding pared
    // down, which read as noticeably taller than the transaction list's
    // own compact rows.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AmcDetailScreen(
              providerKey: p.key,
              providerName: p.name,
              allInvestments: allInvestments,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.account_balance_outlined, color: primary, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('(${p.count})', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.invested > 0)
                    Text('-${Formatters.currency(p.invested)}', style: TextStyle(color: primary, fontSize: 12)),
                  if (p.redeemed > 0)
                    Text('+${Formatters.currency(p.redeemed)}',
                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
