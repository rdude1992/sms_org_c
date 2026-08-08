import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../utils/search_snippet.dart';
import '../widgets/category_badge.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/direction_badge.dart';
import '../widgets/multi_select_bar.dart';
import '../widgets/ui/empty_state.dart';
import '../widgets/ui/filter_chip_bar.dart';
import '../widgets/ui/skeleton.dart';
import 'drafts_screen.dart';
import 'starred_screen.dart';
import 'thread_screen.dart';

enum _InboxMenuAction { starred, drafts }

/// Bottom-nav "Inbox" tab — merges what used to be two separate tabs
/// (Chats, All) into one screen with a toggle between them, so the app
/// isn't asking "which of these two lists do you want" as two different
/// destinations. Which layout is showing is provider state
/// ([SmsProvider.inboxView]), persisted to disk, so it survives both
/// switching away to another tab and a cold app restart — not just
/// staying alive in this widget's local state while the app runs.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  void _startSearch() {
    setState(() => _isSearching = true);
  }

  void _stopSearch(SmsProvider provider, InboxView view) {
    _searchController.clear();
    if (view == InboxView.chats) {
      provider.setChatSearchQuery('');
    } else {
      provider.setSearchQuery('');
    }
    setState(() => _isSearching = false);
  }

  /// Switching layouts mid-search would leave the search box showing text
  /// that's bound to a query field the new layout doesn't read from
  /// (chatSearchQuery vs searchQuery are tracked separately), so close
  /// search rather than carry a stale-looking box across the toggle.
  void _switchView(SmsProvider provider, InboxView view) {
    if (_isSearching) _stopSearch(provider, provider.inboxView);
    provider.setInboxView(view);
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
        final view = provider.inboxView;

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
                          decoration: InputDecoration(
                            hintText: view == InboxView.chats ? 'Search chats' : 'Search messages',
                            border: InputBorder.none,
                          ),
                          onChanged:
                              view == InboxView.chats ? provider.setChatSearchQuery : provider.setSearchQuery,
                        )
                      : const Text('Inbox'),
                  actions: [
                    if (_isSearching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _stopSearch(provider, view),
                      )
                    else ...[
                      if (!provider.isDefaultSmsApp)
                        IconButton(
                          icon: const Icon(Icons.warning_amber_outlined, color: Color(0xFFF59E0B)),
                          tooltip: 'Not the default SMS app',
                          onPressed: () => provider.requestDefaultSmsRole(),
                        ),
                      IconButton(
                        icon: Icon(
                          provider.showUnreadOnly
                              ? Icons.mark_email_unread
                              : Icons.mark_email_unread_outlined,
                          color: provider.showUnreadOnly ? Theme.of(context).colorScheme.primary : null,
                        ),
                        tooltip: provider.showUnreadOnly ? 'Show all' : 'Show unread only',
                        onPressed: () => provider.setShowUnreadOnly(!provider.showUnreadOnly),
                      ),
                      IconButton(
                        icon: Icon(
                          view == InboxView.chats ? Icons.list_alt_outlined : Icons.chat_bubble_outline,
                        ),
                        tooltip: view == InboxView.chats ? 'Switch to list view' : 'Switch to chat view',
                        onPressed: () => _switchView(
                          provider,
                          view == InboxView.chats ? InboxView.messages : InboxView.chats,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _startSearch,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: provider.refresh,
                      ),
                      PopupMenuButton<_InboxMenuAction>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) {
                          final screen = switch (action) {
                            _InboxMenuAction.starred => const StarredScreen(),
                            _InboxMenuAction.drafts => const DraftsScreen(),
                          };
                          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _InboxMenuAction.starred,
                            child: Row(
                              children: [
                                Icon(Icons.star_outline),
                                SizedBox(width: 12),
                                Text('Starred messages'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: _InboxMenuAction.drafts,
                            child: Row(
                              children: [
                                Icon(Icons.drafts_outlined),
                                SizedBox(width: 12),
                                Text('Drafts'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
          body: view == InboxView.chats ? _ChatsBody(provider: provider) : _MessagesBody(provider: provider),
        );
      },
    );
  }
}

class _ChatsBody extends StatelessWidget {
  final SmsProvider provider;
  const _ChatsBody({required this.provider});

  @override
  Widget build(BuildContext context) {
    final conversations = provider.filteredConversations;
    final searching = provider.chatSearchQuery.trim().isNotEmpty;

    Widget body;
    if (provider.state == LoadState.loading && conversations.isEmpty) {
      body = const SkeletonList();
    } else if (provider.state == LoadState.error) {
      body = Center(child: Text('Could not load messages: ${provider.error}'));
    } else if (conversations.isEmpty) {
      body = EmptyState(
        icon: searching ? Icons.search_off_outlined : Icons.chat_bubble_outline,
        title: searching
            ? 'No chats match "${provider.chatSearchQuery.trim()}"'
            : provider.showUnreadOnly
                ? 'No unread chats'
                : provider.activeCategoryFilter != null
                    ? 'No conversations in this category'
                    : 'No conversations yet',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final conversation = conversations[index];
            final selected = provider.selectedIds.contains(conversation.latest.id);
            final scheme = Theme.of(context).colorScheme;
            final unread = conversation.unreadCount > 0;
            final pinned = provider.isPinned(conversation.threadId);
            return Slidable(
              key: ValueKey(conversation.threadId),
              enabled: !provider.isSelecting,
              startActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.5,
                children: [
                  SlidableAction(
                    onPressed: (_) => provider.togglePinned(conversation.threadId),
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: pinned ? 'Unpin' : 'Pin',
                  ),
                  SlidableAction(
                    onPressed: (_) => provider.setConversationRead(conversation, unread),
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    icon: unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                    label: unread ? 'Read' : 'Unread',
                  ),
                ],
              ),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.28,
                children: [
                  SlidableAction(
                    onPressed: (_) => provider.deleteConversation(conversation),
                    backgroundColor: scheme.error,
                    foregroundColor: Colors.white,
                    icon: Icons.delete_outline,
                    label: 'Delete',
                  ),
                ],
              ),
              child: ConversationTile(
                conversation: conversation,
                displayName: provider.displayNameFor(conversation.address),
                selected: selected,
                selectionMode: provider.isSelecting,
                pinned: pinned,
                searchQuery: provider.chatSearchQuery,
                onTap: () {
                  if (provider.isSelecting) {
                    provider.toggleSelected(conversation.latest.id);
                  } else {
                    final preview = conversation.previewFor(provider.chatSearchQuery);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ThreadScreen(
                          threadId: conversation.threadId,
                          highlightMessageId: provider.chatSearchQuery.trim().isEmpty ? null : preview.id,
                        ),
                      ),
                    );
                  }
                },
                onLongPress: () => provider.toggleSelected(conversation.latest.id),
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        _CategoryFilterBar(provider: provider),
        Expanded(child: body),
      ],
    );
  }
}

class _MessagesBody extends StatelessWidget {
  final SmsProvider provider;
  const _MessagesBody({required this.provider});

  @override
  Widget build(BuildContext context) {
    final messages = provider.filteredMessages;
    final searching = provider.searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        _CategoryFilterBar(provider: provider),
        Expanded(
          child: provider.state == LoadState.loading && messages.isEmpty
              ? const SkeletonList()
              : messages.isEmpty
                  ? EmptyState(
                      icon: searching ? Icons.search_off_outlined : Icons.inbox_outlined,
                      title: searching
                          ? 'No messages match "${provider.searchQuery.trim()}"'
                          : provider.showUnreadOnly
                              ? 'No unread messages'
                              : 'No messages in this category',
                    )
                  : _StickyMessageList(provider: provider, messages: messages),
        ),
      ],
    );
  }
}

/// The flat "all messages" list, grouped by calendar day with a pinned
/// header per group — like the thread view's date separators, but sticky:
/// the header for whichever day is on screen stays put instead of
/// scrolling away with its messages.
class _StickyMessageList extends StatelessWidget {
  final SmsProvider provider;
  final List<SmsMessage> messages;
  const _StickyMessageList({required this.provider, required this.messages});

  @override
  Widget build(BuildContext context) {
    final groups = _groupMessagesByDate(messages);
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final group in groups) ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _DateHeaderDelegate(Formatters.dateLabel(group.date)),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _MessageRow(provider: provider, message: group.items[index]),
                childCount: group.items.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateGroup {
  final DateTime date;
  final List<SmsMessage> items;
  _DateGroup(this.date, this.items);
}

List<_DateGroup> _groupMessagesByDate(List<SmsMessage> messages) {
  final groups = <_DateGroup>[];
  for (final m in messages) {
    if (groups.isNotEmpty && Formatters.isSameDay(groups.last.date, m.date)) {
      groups.last.items.add(m);
    } else {
      groups.add(_DateGroup(m.date, [m]));
    }
  }
  return groups;
}

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  const _DateHeaderDelegate(this.label);

  @override
  double get minExtent => 32;
  @override
  double get maxExtent => 32;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 32,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DateHeaderDelegate oldDelegate) => oldDelegate.label != label;
}

class _MessageRow extends StatelessWidget {
  final SmsProvider provider;
  final SmsMessage message;
  const _MessageRow({required this.provider, required this.message});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final selected = provider.selectedIds.contains(m.id);
    final unread = !m.read && m.isIncoming;
    final scheme = Theme.of(context).colorScheme;
    return Slidable(
      key: ValueKey(m.id),
      enabled: !provider.isSelecting,
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => provider.setMessageRead(m.id, unread),
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            icon: unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
            label: unread ? 'Read' : 'Unread',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => provider.deleteMessage(m.id),
            backgroundColor: scheme.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primary.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        minVerticalPadding: 10,
        leading: provider.isSelecting
            ? Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: m.category.color.withOpacity(0.15),
                    child: Icon(m.category.icon, color: m.category.color, size: 18),
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
                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
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
          child: SearchPreviewText(
            body: m.body,
            query: provider.searchQuery,
            baseStyle: TextStyle(
              color: unread ? scheme.onSurface.withOpacity(0.85) : scheme.onSurfaceVariant,
              fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
            ),
            matchColor: scheme.primary,
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
                builder: (_) => ThreadScreen(threadId: m.threadId, highlightMessageId: m.id),
              ),
            );
          }
        },
        onLongPress: () => provider.toggleSelected(m.id),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  final SmsProvider provider;
  const _CategoryFilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return FilterChipBar<SmsCategory?>(
      values: [null, for (final cat in SmsCategory.values) cat],
      selected: provider.activeCategoryFilter,
      labelBuilder: (category) => category?.label ?? 'All',
      onSelected: provider.setCategoryFilter,
    );
  }
}
