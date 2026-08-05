import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/multi_select_bar.dart';
import 'thread_screen.dart';

class ConversationsTab extends StatelessWidget {
  const ConversationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final conversations = provider.conversations;

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
                  title: const Text('Chats'),
                  actions: [
                    if (!provider.isDefaultSmsApp)
                      IconButton(
                        icon: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
                        tooltip: 'Not the default SMS app',
                        onPressed: () => provider.requestDefaultSmsRole(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: provider.refresh,
                    ),
                  ],
                ),
          body: _buildBody(context, provider, conversations),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, SmsProvider provider, List conversations) {
    if (provider.state == LoadState.loading && conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.state == LoadState.error) {
      return Center(child: Text('Could not load messages: ${provider.error}'));
    }
    if (conversations.isEmpty) {
      return const Center(child: Text('No conversations yet.'));
    }
    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.separated(
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          final selected = provider.selectedIds.contains(conversation.latest.id);
          return ConversationTile(
            conversation: conversation,
            displayName: provider.displayNameFor(conversation.address),
            selected: selected,
            selectionMode: provider.isSelecting,
            onTap: () {
              if (provider.isSelecting) {
                provider.toggleSelected(conversation.latest.id);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ThreadScreen(threadId: conversation.threadId)),
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
