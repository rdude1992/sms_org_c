import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/category_badge.dart';
import '../widgets/multi_select_bar.dart';
import 'thread_screen.dart';

class AllMessagesTab extends StatelessWidget {
  const AllMessagesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final messages = provider.filteredMessages;

        return Scaffold(
          appBar: provider.isSelecting
              ? MultiSelectAppBar(
                  selectedCount: provider.selectedIds.length,
                  onClear: provider.clearSelection,
                  onMarkRead: () => provider.markSelectedRead(true),
                  onMarkUnread: () => provider.markSelectedRead(false),
                  onDelete: provider.deleteSelected,
                )
              : AppBar(title: const Text('All Messages')),
          body: Column(
            children: [
              _CategoryFilterBar(provider: provider),
              const Divider(height: 1),
              Expanded(
                child: provider.state == LoadState.loading && messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : messages.isEmpty
                        ? const Center(child: Text('No messages in this category.'))
                        : ListView.separated(
                            itemCount: messages.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
                            itemBuilder: (context, index) {
                              final m = messages[index];
                              final selected = provider.selectedIds.contains(m.id);
                              return ListTile(
                                selected: selected,
                                selectedTileColor:
                                    Theme.of(context).colorScheme.primary.withOpacity(0.06),
                                leading: provider.isSelecting
                                    ? Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: selected
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.grey,
                                      )
                                    : CircleAvatar(
                                        backgroundColor: m.category.color.withOpacity(0.15),
                                        child: Icon(m.category.icon,
                                            color: m.category.color, size: 18),
                                      ),
                                title: Text(
                                  provider.displayNameFor(m.address),
                                  style: TextStyle(
                                    fontWeight:
                                        (!m.read && m.isIncoming) ? FontWeight.bold : FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  m.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      Formatters.relativeOrTime(m.date),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 4),
                                    CategoryBadge(category: m.category, compact: true),
                                  ],
                                ),
                                onTap: () {
                                  if (provider.isSelecting) {
                                    provider.toggleSelected(m.id);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ThreadScreen(threadId: m.threadId),
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
