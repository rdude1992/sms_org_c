import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
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

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.displayName,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
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
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: latest.category.color.withOpacity(0.15),
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(color: latest.category.color, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 14),
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
                              fontSize: 15,
                              color: unread ? scheme.onSurface : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Formatters.relativeOrTime(latest.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SearchPreviewText(
                            body: previewMessage.body,
                            query: query,
                            baseStyle: TextStyle(
                              color: unread ? scheme.onSurface.withOpacity(0.85) : scheme.onSurfaceVariant,
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
    );
  }
}
