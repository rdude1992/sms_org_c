import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../utils/formatters.dart';
import 'category_badge.dart';

class ConversationTile extends StatelessWidget {
  final SmsConversation conversation;
  final String displayName;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.displayName,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final latest = conversation.latest;
    final unread = conversation.unreadCount > 0;

    return Material(
      color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                )
              else
                CircleAvatar(
                  radius: 22,
                  backgroundColor: latest.category.color.withOpacity(0.15),
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(color: latest.category.color, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Formatters.relativeOrTime(latest.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread ? Theme.of(context).colorScheme.primary : Colors.grey,
                            fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            latest.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread ? null : Colors.grey,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CategoryBadge(category: latest.category, compact: true),
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
