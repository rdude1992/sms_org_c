import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/sim_info.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../utils/formatters.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multi_select_bar.dart';
import '../widgets/sim_picker.dart';
import 'compose_screen.dart';

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

  int? _selectedSubscriptionId;
  bool _simInitialized = false;

  @override
  void initState() {
    super.initState();
    _highlightedId = widget.highlightMessageId;
    // Opening a thread should mark its unread messages read, same as any
    // other SMS app — fire once after the first frame rather than in
    // build(), which reruns on every provider notifyListeners().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SmsProvider>().markThreadRead(widget.threadId);
    });
  }

  void _initSelectedSim(List<SimInfo> sims) {
    if (_simInitialized) return;
    _simInitialized = true;
    if (sims.isNotEmpty) _selectedSubscriptionId = sims.first.subscriptionId;
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
        _initSelectedSim(provider.activeSims);

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
                          onLongPress: () {
                            if (provider.isSelecting) {
                              provider.toggleSelected(m.id);
                            } else {
                              _showMessageActions(context, provider, m);
                            }
                          },
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
                      if (provider.activeSims.length > 1) ...[
                        SimPicker(
                          sims: provider.activeSims,
                          selectedSubscriptionId: _selectedSubscriptionId,
                          onChanged: (id) => setState(() => _selectedSubscriptionId = id),
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                      ],
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
                          await provider.sendSms(
                            conversation.address,
                            text,
                            subscriptionId: _selectedSubscriptionId,
                          );
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

/// Long-press-on-a-bubble context menu — copy / forward / select / delete —
/// in place of jumping straight into multi-select the way it used to.
/// "Select" is kept as an explicit option here so multi-select is still
/// reachable, just one tap deeper instead of the only long-press outcome.
void _showMessageActions(BuildContext context, SmsProvider provider, SmsMessage message) {
  final scheme = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy text'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(ClipboardData(text: message.body));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied message'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward_outlined),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ComposeScreen(initialBody: message.body)),
                );
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
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Delete', style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDeleteMessage(context, provider, message.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _confirmDeleteMessage(BuildContext context, SmsProvider provider, int id) async {
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
