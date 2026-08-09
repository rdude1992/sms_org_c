import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../utils/search_snippet.dart';
import '../widgets/category_badge.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/direction_badge.dart';
import '../widgets/multi_select_bar.dart';
import '../widgets/ui/empty_state.dart';
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

/// Every category tab shown across the Inbox, in order — a leading "All"
/// (null) followed by each [SmsCategory]. Shared by both Inbox layouts so
/// they swipe through the exact same set of tabs.
const _categoryTabs = <SmsCategory?>[null, ...SmsCategory.values];

class _ChatsBody extends StatefulWidget {
  final SmsProvider provider;
  const _ChatsBody({required this.provider});

  @override
  State<_ChatsBody> createState() => _ChatsBodyState();
}

class _ChatsBodyState extends State<_ChatsBody> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = _categoryTabs.indexOf(widget.provider.activeCategoryFilter);
    _tabController = TabController(
      length: _categoryTabs.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    )..addListener(_syncCategoryFilter);
  }

  // Fires on both a tab tap and a swipe — keeps SmsProvider's shared
  // activeCategoryFilter in step with whichever tab is now showing, so it's
  // still correct if the user switches to the Messages layout and back.
  void _syncCategoryFilter() {
    final category = _categoryTabs[_tabController.index];
    if (category != widget.provider.activeCategoryFilter) {
      widget.provider.setCategoryFilter(category);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_syncCategoryFilter);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final category in _categoryTabs) Tab(text: category?.label ?? 'All')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final category in _categoryTabs)
                _ConversationListView(provider: widget.provider, category: category),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversationListView extends StatelessWidget {
  final SmsProvider provider;
  final SmsCategory? category;
  const _ConversationListView({required this.provider, required this.category});

  @override
  Widget build(BuildContext context) {
    final conversations = provider.conversationsForCategory(category);
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
                : category != null
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
            final pinned = provider.isPinned(conversation.threadId);
            return ConversationTile(
              key: ValueKey(conversation.threadId),
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
              onLongPress: () {
                if (provider.isSelecting) {
                  provider.toggleSelected(conversation.latest.id);
                } else {
                  _showConversationActions(context, provider, conversation);
                }
              },
            );
          },
        ),
      );
    }

    return body;
  }
}

class _MessagesBody extends StatefulWidget {
  final SmsProvider provider;
  const _MessagesBody({required this.provider});

  @override
  State<_MessagesBody> createState() => _MessagesBodyState();
}

class _MessagesBodyState extends State<_MessagesBody> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = _categoryTabs.indexOf(widget.provider.activeCategoryFilter);
    _tabController = TabController(
      length: _categoryTabs.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    )..addListener(_syncCategoryFilter);
  }

  void _syncCategoryFilter() {
    final category = _categoryTabs[_tabController.index];
    if (category != widget.provider.activeCategoryFilter) {
      widget.provider.setCategoryFilter(category);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_syncCategoryFilter);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final category in _categoryTabs) Tab(text: category?.label ?? 'All')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final category in _categoryTabs)
                _MessagesListView(provider: widget.provider, category: category),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessagesListView extends StatelessWidget {
  final SmsProvider provider;
  final SmsCategory? category;
  const _MessagesListView({required this.provider, required this.category});

  @override
  Widget build(BuildContext context) {
    final messages = provider.messagesForCategory(category);
    final searching = provider.searchQuery.trim().isNotEmpty;

    if (provider.state == LoadState.loading && messages.isEmpty) {
      return const SkeletonList();
    }
    if (messages.isEmpty) {
      return EmptyState(
        icon: searching ? Icons.search_off_outlined : Icons.inbox_outlined,
        title: searching
            ? 'No messages match "${provider.searchQuery.trim()}"'
            : provider.showUnreadOnly
                ? 'No unread messages'
                : 'No messages in this category',
      );
    }
    return _StickyMessageList(provider: provider, messages: messages);
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
    return ListTile(
      key: ValueKey(m.id),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.isCategoryOverridden) ...[
                Tooltip(
                  message: 'Manually set',
                  child: Icon(Icons.edit, size: 10, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 3),
              ],
              CategoryBadge(category: m.category, compact: true, showLabel: false),
            ],
          ),
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
      onLongPress: () {
        if (provider.isSelecting) {
          provider.toggleSelected(m.id);
        } else {
          _showMessageRowActions(context, provider, m);
        }
      },
    );
  }
}

/// Long-press-on-a-row context menu for a conversation — pin/unpin, mark
/// read/unread, select, delete — in place of the swipe actions this list
/// used to have. "Select" is kept as an explicit option here so multi-select
/// is still reachable, just one tap deeper instead of the only long-press
/// outcome (matches the pattern ThreadScreen already uses for messages).
void _showConversationActions(BuildContext context, SmsProvider provider, SmsConversation conversation) {
  final scheme = Theme.of(context).colorScheme;
  final unread = conversation.unreadCount > 0;
  final pinned = provider.isPinned(conversation.threadId);
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(pinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.togglePinned(conversation.threadId);
              },
            ),
            ListTile(
              leading: Icon(unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined),
              title: Text(unread ? 'Mark as read' : 'Mark as unread'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.setConversationRead(conversation, unread);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.toggleSelected(conversation.latest.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete conversation', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteConversation(context, provider, conversation);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmDeleteConversation(
    BuildContext context, SmsProvider provider, SmsConversation conversation) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete conversation?'),
      content: const Text('All messages in this conversation will be deleted. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  if (confirmed == true) await provider.deleteConversation(conversation);
}

/// Long-press-on-a-row context menu for a flat message-list row — mark
/// read/unread, select, delete — see [_showConversationActions].
void _showMessageRowActions(BuildContext context, SmsProvider provider, SmsMessage message) {
  final scheme = Theme.of(context).colorScheme;
  final unread = !message.read && message.isIncoming;
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined),
              title: Text(unread ? 'Mark as read' : 'Mark as unread'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.setMessageRead(message.id, unread);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Change category'),
              subtitle: Text(
                message.isCategoryOverridden ? '${message.category.label} · manually set' : message.category.label,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showCategoryPickerSheet(context, provider, message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.toggleSelected(message.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteMessageRow(context, provider, message.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmDeleteMessageRow(BuildContext context, SmsProvider provider, int id) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text('This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
        ),
      ],
    ),
  );
  if (confirmed == true) await provider.deleteMessage(id);
}
