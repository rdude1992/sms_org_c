import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/investment_tile.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/total_stat.dart';

/// Drilldown target for the Insights "Investments" card — mirrors
/// TransactionListScreen's All/split-direction tab pattern, split here into
/// All/Invested/Redeemed since that's the distinction InvestmentKind draws,
/// plus a "By AMC" tab that groups events by AMC/broker (see
/// [InvestmentEvent.providerGroupKey]) with its own drilldown back into
/// this same screen, filtered to that provider.
class InvestmentListScreen extends StatelessWidget {
  final String? subtitle;
  final List<InvestmentEvent> investments;

  const InvestmentListScreen({super.key, required this.investments, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...investments]..sort((a, b) => b.date.compareTo(a.date));
    final invested = sorted.where((i) => !i.kind.isRedemption).toList();
    final redeemed = sorted.where((i) => i.kind.isRedemption).toList();
    final investedTotal = invested.fold<double>(0, (a, i) => a + i.amount);
    final redeemedTotal = redeemed.fold<double>(0, (a, i) => a + i.amount);
    final providers = _groupByProvider(sorted);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Investments'),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(subtitle == null ? 48 : 68),
            child: Column(
              children: [
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'All (${sorted.length})'),
                    Tab(text: 'Invested (${invested.length})'),
                    Tab(text: 'Redeemed (${redeemed.length})'),
                    Tab(text: 'By AMC (${providers.length})'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: sorted.isEmpty
            ? const EmptyState(icon: Icons.trending_up, title: 'No investment activity in this range')
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
                          child: TotalStat(label: 'Redeemed', value: redeemedTotal, color: const Color(0xFFF59E0B)),
                        ),
                        Text(
                          '${sorted.length} events',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _InvestmentListView(investments: sorted, emptyText: 'No investment activity.'),
                        _InvestmentListView(investments: invested, emptyText: 'Nothing invested.'),
                        _InvestmentListView(investments: redeemed, emptyText: 'Nothing redeemed.'),
                        _AmcListView(providers: providers, subtitle: subtitle),
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

  const _InvestmentListView({required this.investments, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (investments.isEmpty) {
      return EmptyState(icon: Icons.trending_up, title: emptyText);
    }
    return ListView.separated(
      itemCount: investments.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) => InvestmentTile(investment: investments[index]),
    );
  }
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
    if (i.kind.isRedemption) {
      summary.redeemed += i.amount;
    } else {
      summary.invested += i.amount;
    }
    summary.events.add(i);
  }
  return map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

class _AmcListView extends StatelessWidget {
  final List<_ProviderSummary> providers;
  final String? subtitle;

  const _AmcListView({required this.providers, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return const EmptyState(icon: Icons.trending_up, title: 'No investment activity.');
    }
    return ListView.separated(
      itemCount: providers.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final p = providers[index];
        final primary = Theme.of(context).colorScheme.primary;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: primary.withOpacity(0.12),
            child: Icon(Icons.account_balance_outlined, color: primary, size: 18),
          ),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${p.count} event${p.count == 1 ? '' : 's'}'),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (p.invested > 0)
                Text('-${Formatters.currency(p.invested)}',
                    style: TextStyle(color: primary, fontSize: 12)),
              if (p.redeemed > 0)
                Text('+${Formatters.currency(p.redeemed)}',
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InvestmentListScreen(investments: p.events, subtitle: p.name),
            ),
          ),
        );
      },
    );
  }
}
