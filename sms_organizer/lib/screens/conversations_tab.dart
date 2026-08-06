import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/multi_select_bar.dart';
import 'thread_screen.dart';

class ConversationsTab extends StatefulWidget {
  const ConversationsTab({super.key});

  @override
  State<ConversationsTab> createState() => _ConversationsTabState();
}

class _ConversationsTabState extends State<ConversationsTab> {
  bool _isSearching = false;
  final _searchController = TextEditingController();

  void _startSearch() {
    setState(() => _isSearching = true);
  }

  void _stopSearch(SmsProvider provider) {
    _searchController.clear();
    provider.setChatSearchQuery('');
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
        final conversations = provider.filteredConversations;
        final searching = provider.chatSearchQuery.trim().isNotEmpty;

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
                            hintText: 'Search chats',
                            border: InputBorder.none,
                          ),
                          onChanged: provider.setChatSearchQuery,
                        )
                      : const Text('Chats'),
                  actions: [
                    if (_isSearching)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _stopSearch(provider),
                      )
                    else ...[
                      if (!provider.isDefaultSmsApp)
                        IconButton(
                          icon: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
                          tooltip: 'Not the default SMS app',
                          onPressed: () => provider.requestDefaultSmsRole(),
                        ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _startSearch,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: provider.refresh,
                      ),
                    ],
                  ],
                ),
          body: _buildBody(context, provider, conversations, searching),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    SmsProvider provider,
    List<SmsConversation> conversations,
    bool searching,
  ) {
    if (provider.state == LoadState.loading && conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.state == LoadState.error) {
      return Center(child: Text('Could not load messages: ${provider.error}'));
    }
    if (conversations.isEmpty) {
      return Center(
        child: Text(
          searching
              ? 'No chats match "${provider.chatSearchQuery.trim()}".'
              : 'No conversations yet.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 78),
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          final selected = provider.selectedIds.contains(conversation.latest.id);
          return ConversationTile(
            conversation: conversation,
            displayName: provider.displayNameFor(conversation.address),
            selected: selected,
            selectionMode: provider.isSelecting,
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
                      highlightMessageId:
                          provider.chatSearchQuery.trim().isEmpty ? null : preview.id,
                    ),
                  ),
                );
              }
            },
            onLongPress: () => provider.toggleSelected(conversation.latest.id),
          );
        },
      ),
    );
  }
}
