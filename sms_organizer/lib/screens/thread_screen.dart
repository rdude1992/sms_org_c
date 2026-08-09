import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../models/category.dart';
import '../models/sim_info.dart';
import '../models/sms_message.dart';
import '../providers/sms_provider.dart';
import '../utils/address_utils.dart';
import '../utils/formatters.dart';
import '../widgets/category_picker_sheet.dart';
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

  /// Reply text to pre-fill, taking priority over any saved draft — set
  /// when the compose screen hands off to an existing thread after the
  /// user picks a contact they'd already started typing a message to, so
  /// that in-progress text isn't lost in the handoff.
  final String? initialReplyText;

  const ThreadScreen({
    super.key,
    required this.threadId,
    this.highlightMessageId,
    this.initialReplyText,
  });

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

  // The draft (if any) saved for this thread — loaded once into the reply
  // box below, and kept up to date on the way out so leaving with unsent
  // text behaves like any other messaging app instead of silently losing it.
  int? _draftId;
  bool _draftLoaded = false;
  String? _address;
  late final SmsProvider _provider;

  @override
  void initState() {
    super.initState();
    _highlightedId = widget.highlightMessageId;
    _provider = context.read<SmsProvider>();
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

  /// Pre-fills the reply box from a saved draft the first time [provider]
  /// has actually finished a sync — done once, guarded by [_draftLoaded], so
  /// it never clobbers text the user has since typed.
  void _loadDraftIfNeeded(SmsProvider provider) {
    if (_draftLoaded || provider.state != LoadState.ready) return;
    _draftLoaded = true;
    for (final d in provider.drafts) {
      if (d.threadId == widget.threadId) {
        _draftId = d.id;
        _replyController.text = d.body;
        break;
      }
    }
    // Text carried over from the compose screen wins over whatever was on
    // disk — it hasn't been saved anywhere yet, so the on-disk draft (if
    // any) would otherwise silently clobber it.
    final initialText = widget.initialReplyText?.trim();
    if (initialText != null && initialText.isNotEmpty) {
      _replyController.text = initialText;
    }
  }

  @override
  void dispose() {
    _persistDraftOnExit();
    _replyController.dispose();
    super.dispose();
  }

  /// Leaving the thread with unsent reply text saves/updates its draft;
  /// leaving with the box empty removes a stale one. Fire-and-forget since
  /// dispose() can't be awaited — the provider outlives this widget either
  /// way.
  void _persistDraftOnExit() {
    final address = _address;
    if (address == null) return;
    final text = _replyController.text.trim();
    if (text.isEmpty) {
      if (_draftId != null) _provider.deleteMessage(_draftId!);
    } else {
      _provider.saveDraft(address, text, existingId: _draftId);
    }
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
        _address = conversation.address;
        // Shortcodes and alphanumeric DLT sender IDs (bank/OTP/promo alerts)
        // are one-way — the carrier just drops an SMS sent back to one, so
        // showing a reply box that can never actually deliver anything
        // would be misleading. Forwarding a message elsewhere still works
        // via the per-bubble long-press menu either way.
        final canReply = isPhoneNumberAddress(conversation.address);
        final messages = conversation.messages.reversed.toList(); // oldest first for chat view

        _loadDraftIfNeeded(provider);

        // Land on the highlighted message if the thread was opened from a
        // search/tap-through, otherwise on the newest message — like any
        // other chat app opens at the bottom, not wherever the list's
        // estimated item extents happen to settle.
        //
        // [alignment] positions an item's TOP edge at that fraction of the
        // viewport (0 = top, 1 = bottom) — it has no notion of an item's
        // bottom edge. Targeting the real last message with alignment 1
        // would put *its* top at the viewport's bottom, leaving almost the
        // whole bubble cut off below the fold. Targeting the zero-height
        // sentinel item just past the end (see itemCount/itemBuilder below)
        // instead means that phantom item's top — which sits exactly where
        // the real last message's bottom is — lands at the viewport's
        // bottom, so the last message ends up fully visible with nothing
        // left to scroll for.
        //
        // The highlighted-message case doesn't need that trick (0.4 puts a
        // reasonable amount of context above it without risking cutting off
        // a tall bubble) — it's set to the same value _scrollToHighlightIfNeeded's
        // follow-up scrollTo() settles on below, so that animated correction
        // only has to travel a short, subtle distance instead of visibly
        // snapping from a completely different spot.
        final highlightIndex =
            widget.highlightMessageId == null ? -1 : messages.indexWhere((m) => m.id == widget.highlightMessageId);
        final initialIndex = highlightIndex != -1 ? highlightIndex : messages.length;
        final initialAlignment = highlightIndex != -1 ? 0.4 : 1.0;

        _scrollToHighlightIfNeeded(messages);
        _initSelectedSim(provider.activeSims);

        final visibleIds = messages.map((m) => m.id).toList();
        final allSelected = visibleIds.isNotEmpty && visibleIds.every(provider.selectedIds.contains);

        return Scaffold(
          appBar: provider.isSelecting
              ? MultiSelectAppBar(
                  selectedCount: provider.selectedIds.length,
                  onClear: provider.clearSelection,
                  onMarkRead: () => provider.markSelectedRead(true),
                  onMarkUnread: () => provider.markSelectedRead(false),
                  onDelete: provider.deleteSelected,
                  allSelected: allSelected,
                  onToggleSelectAll: () =>
                      allSelected ? provider.clearSelection() : provider.selectIds(visibleIds),
                )
              : AppBar(
                  title: Text(provider.displayNameFor(conversation.address)),
                  actions: [
                    IconButton(
                      icon: Icon(
                        provider.isPinned(conversation.threadId) ? Icons.push_pin : Icons.push_pin_outlined,
                      ),
                      tooltip: provider.isPinned(conversation.threadId) ? 'Unpin' : 'Pin conversation',
                      onPressed: () => provider.togglePinned(conversation.threadId),
                    ),
                  ],
                ),
          body: Column(
            children: [
              Expanded(
                child: ScrollablePositionedList.builder(
                  itemScrollController: _itemScrollController,
                  initialScrollIndex: initialIndex < 0 ? 0 : initialIndex,
                  initialAlignment: initialAlignment,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  // +1 for the trailing zero-height sentinel — see the
                  // initialIndex/initialAlignment comment above for why.
                  itemCount: messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == messages.length) return const SizedBox.shrink();
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
                          starred: provider.isStarred(m.id),
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
              if (canReply)
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
                            if (_draftId != null) {
                              provider.deleteMessage(_draftId!);
                              _draftId = null;
                            }
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
                )
              else
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "This sender doesn't accept replies",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
              leading: Icon(provider.isStarred(message.id) ? Icons.star : Icons.star_outline),
              title: Text(provider.isStarred(message.id) ? 'Unstar' : 'Star'),
              onTap: () {
                Navigator.pop(sheetContext);
                provider.toggleStarred(message.id);
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
