import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/category_badge.dart';
import '../widgets/direction_badge.dart';
import '../widgets/multi_select_bar.dart';
import 'thread_screen.dart';

class AllMessagesTab extends StatefulWidget {
  const AllMessagesTab({super.key});

  @override
  State<AllMessagesTab> createState() => _AllMessagesTabState();
}

class _AllMessagesTabState extends State<AllMessagesTab> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  void _startSearch() {
    setState(() => _isSearching = true);
  }

  void _stopSearch(SmsProvider provider) {
    _searchController.clear();
    provider.setSearchQuery('');
    setState(() => _isSearching = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final messages = provider.filteredMessages;
        final searching = provider.searchQuery.trim().isNotEmpty;

        return Scaffold(
          appBar: provider.isSelecting
              ? MultiSelectAppBar(
                  selectedCount: provider.selectedIds.length,
                  onClear: provider.clearSelection,
                  onMarkRead: () => provider.markSelectedRead(true),
                  onMarkUnread: () => provider.markSelectedRead(false),
                  onDelete: provider.deleteSelected,
                )
              : AppBar(
                  title: _isSearching
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: 'Search messages',
                            border: InputBorder.none,
                          ),
                          onChanged: provider.setSearchQuery,
                        )
                      : const Text('All Messages'),
                  actions: [
                    if (_isSearching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _stopSearch(provider),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _startSearch,
                      ),
                  ],
                ),
          body: Column(
            children: [
              _CategoryFilterBar(provider: provider),
              const Divider(height: 1),
              Expanded(
                child: provider.state == LoadState.loading && messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
                        ? Center(
                            child: Text(
                              searching
                                  ? 'No messages match "${provider.searchQuery.trim()}".'
                                  : 'No messages in this category.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: messages.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                            itemBuilder: (context, index) {
                              final m = messages[index];
                              final selected = provider.selectedIds.contains(m.id);
                              final unread = !m.read && m.isIncoming;
                              final scheme = Theme.of(context).colorScheme;
                              return ListTile(
                                selected: selected,
                                selectedTileColor: scheme.primary.withOpacity(0.06),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                minVerticalPadding: 10,
                                leading: provider.isSelecting
                                    ? Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: selected ? scheme.primary : scheme.outline,
                                      )
                                    : Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: m.category.color.withOpacity(0.15),
                                            child: Icon(m.category.icon,
                                                color: m.category.color, size: 18),
                                          ),
                                          Positioned(
                                            bottom: -2,
                                            right: -2,
                                            child: DirectionBadge(isIncoming: m.isIncoming),
                                          ),
                                        ],
                                      ),
                                title: Row(
                                  children: [
                                    if (unread) ...[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: scheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        provider.displayNameFor(m.address),
                                        style: TextStyle(
                                          fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                                          color: unread ? scheme.onSurface : null,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    m.body,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: unread
                                          ? scheme.onSurface.withOpacity(0.85)
                                          : scheme.onSurfaceVariant,
                                      fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (m.simSlot != null) ...[
                                          Text(
                                            'SIM ${m.simSlot! + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          Formatters.relativeOrTime(m.date),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: unread ? scheme.primary : scheme.onSurfaceVariant,
                                            fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    CategoryBadge(category: m.category, compact: true, showLabel: false),
                                  ],
                                ),
                                onTap: () {
                                  if (provider.isSelecting) {
                                    provider.toggleSelected(m.id);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ThreadScreen(
                                          threadId: m.threadId,
                                          highlightMessageId: m.id,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                onLongPress: () => provider.toggleSelected(m.id),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final SmsProvider provider;
  const _CategoryFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _chip(context, null, 'All'),
          for (final cat in SmsCategory.values) _chip(context, cat, cat.label),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, SmsCategory? category, String label) {
    final selected = provider.activeCategoryFilter == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => provider.setCategoryFilter(category),
      ),
    );
  }
}
