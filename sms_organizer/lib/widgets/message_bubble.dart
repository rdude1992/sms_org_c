import 'package:flutter/material.dart';
import '../models/sms_message.dart';
import '../utils/formatters.dart';

class MessageBubble extends StatelessWidget {
  final SmsMessage message;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.box == SmsBoxType.sent || message.box == SmsBoxType.outbox;
    final scheme = Theme.of(context).colorScheme;

    final bubbleColor = isOutgoing
        ? scheme.primary
        : (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF262A30)
            : Colors.white);
    final textColor = isOutgoing ? scheme.onPrimary : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? scheme.primary.withOpacity(0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                margin: EdgeInsets.only(
                  left: isOutgoing ? 48 : 12,
                  right: isOutgoing ? 12 : 48,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                    bottomRight: Radius.circular(isOutgoing ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.body, style: TextStyle(color: textColor, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      Formatters.relativeOrTime(message.date),
                      style: TextStyle(
                        color: textColor?.withOpacity(0.7) ?? Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
