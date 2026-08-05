import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multi_select_bar.dart';

class ThreadScreen extends StatefulWidget {
  final int threadId;
  const ThreadScreen({super.key, required this.threadId});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmsProvider>(
      builder: (context, provider, _) {
        final matches = provider.conversations.where((c) => c.threadId == widget.threadId);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Conversation')),
            body: const Center(child: Text('This conversation is empty.')),
          );
        }
        final conversation = matches.first;
        final messages = conversation.messages.reversed.toList(); // oldest first for chat view

        return Scaffold(
          appBar: provider.isSelecting
              ? MultiSelectAppBar(
                  selectedCount: provider.selectedIds.length,
                  onClear: provider.clearSelection,
                  onMarkRead: () => provider.markSelectedRead(true),
                  onMarkUnread: () => provider.markSelectedRead(false),
                  onDelete: provider.deleteSelected,
                )
              : AppBar(title: Text(provider.displayNameFor(conversation.address))),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  reverse: false,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final selected = provider.selectedIds.contains(m.id);
                    return MessageBubble(
                      message: m,
                      selected: selected,
                      selectionMode: provider.isSelecting,
                      onTap: () {
                        if (provider.isSelecting) provider.toggleSelected(m.id);
                      },
                      onLongPress: () => provider.toggleSelected(m.id),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: () async {
                          final text = _replyController.text.trim();
                          if (text.isEmpty) return;
                          _replyController.clear();
                          await provider.sendSms(conversation.address, text);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
