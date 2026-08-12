import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/search_snippet.dart';
import 'category_badge.dart';

class ConversationTile extends StatelessWidget {
  final SmsConversation conversation;
  final String displayName;
  final bool selected;
  final bool selectionMode;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Active chat search query, if any — when set, the preview line shows a
  /// match-centered, highlighted snippet from whichever message in the
  /// thread actually matched (which may not be the latest one) instead of
  /// always previewing the most recent message.
  final String? searchQuery;

  /// Whether the last-message preview panel below this row is open — tapping
  /// the avatar toggles it (see [onAvatarTap]). Lives one level up (in
  /// _ConversationListView's state) rather than here, since this widget gets
  /// torn down and rebuilt on every list refresh.
  final bool expanded;
  final VoidCallback onAvatarTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.displayName,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.expanded,
    required this.onAvatarTap,
    this.pinned = false,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final latest = conversation.latest;
    final unread = conversation.unreadCount > 0;
    final scheme = Theme.of(context).colorScheme;

    final query = (searchQuery ?? '').trim();
    final previewMessage = conversation.previewFor(query);

    return Material(
      color: selected ? scheme.primary.withOpacity(0.08) : Colors.transparent,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected ? scheme.primary : scheme.outline,
                      ),
                    )
                  else
                    // Tapping just the avatar expands/collapses the preview
                    // panel below (see build's trailing AnimatedSize) instead
                    // of opening the thread — a separate InkWell here means
                    // that tap never also triggers the row's own onTap.
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAvatarTap,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: latest.category.color.withOpacity(0.15),
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: latest.category.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (unread) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (pinned) ...[
                              Icon(Icons.push_pin, size: 13, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 14,
                                  color: unread ? scheme.onSurface : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              Formatters.relativeOrTime(latest.date),
                              style: TextStyle(
                                fontSize: 11,
                                color: unread ? scheme.primary : scheme.onSurfaceVariant,
                                fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: SearchPreviewText(
                                body: previewMessage.body,
                                query: query,
                                baseStyle: TextStyle(
                                  color:
                                      unread ? scheme.onSurface.withOpacity(0.85) : scheme.onSurfaceVariant,
                                  fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                                  fontSize: 13,
                                ),
                                matchColor: scheme.primary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (unread)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${conversation.unreadCount}',
                                  style: TextStyle(
                                    color: scheme.onPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            CategoryBadge(category: latest.category, compact: true, showLabel: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expands/collapses inline, full row width, right under the tile
          // it belongs to — a real dropdown out of the list item itself,
          // rather than a small floating popup disconnected from the row.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? MessagePreviewPanel(message: latest)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Inline "peek at a message" panel a row expands to show when its avatar
/// is tapped — lets a user check what a message was about without leaving
/// the list to open the full thread. Shared by ConversationTile (peeking at
/// a chat's latest message) and inbox_screen.dart's flat "All messages"
/// list (peeking at that specific row's message).
class MessagePreviewPanel extends StatelessWidget {
  final SmsMessage message;
  const MessagePreviewPanel({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // Fixed dark-neutral card — deliberately independent of light/dark
    // theme and the terracotta brand accent, same reasoning as
    // MessageBubble's outgoing bubble (see there): a low-key dark "peek"
    // card rather than a theme-tinted one.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.stone900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Formatters.full(message.date),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.darkMutedForeground),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(
              child: Text(
                message.body.isEmpty ? '(no message text)' : message.body,
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.darkOnSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
