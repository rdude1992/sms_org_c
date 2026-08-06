import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multi_select_bar.dart';

class ThreadScreen extends StatefulWidget {
  final int threadId;

  /// If set (e.g. tapping a message in the All Messages list), the thread
  /// scrolls to and briefly highlights this message on open.
  final int? highlightMessageId;

  const ThreadScreen({super.key, required this.threadId, this.highlightMessageId});

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _replyController = TextEditingController();
  final _itemScrollController = ItemScrollController();

  int? _highlightedId;
  bool _didInitialScroll = false;

  @override
  void initState() {
    super.initState();
    _highlightedId = widget.highlightMessageId;
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _scrollToHighlightIfNeeded(List<SmsMessage> messages) {
    if (_didInitialScroll || widget.highlightMessageId == null) return;
    final index = messages.indexWhere((m) => m.id == widget.highlightMessageId);
    if (index == -1) return;
    _didInitialScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemScrollController.isAttached) return;
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.4,
      );
    });

    // Fade the highlight back out after it's had a moment to draw the eye.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedId = null);
    });
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

        _scrollToHighlightIfNeeded(messages);

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
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final selected = provider.selectedIds.contains(m.id);
                    final showDateSeparator =
                        index == 0 || !Formatters.isSameDay(messages[index - 1].date, m.date);
                    return Column(
                      children: [
                        if (showDateSeparator) DateSeparator(date: m.date),
                        MessageBubble(
                          message: m,
                          selected: selected,
                          selectionMode: provider.isSelecting,
                          highlighted: m.id == _highlightedId,
                          onTap: () {
                            if (provider.isSelecting) provider.toggleSelected(m.id);
                          },
                          onLongPress: () => provider.toggleSelected(m.id),
                        ),
                      ],
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
