import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../utils/formatters.dart';
import '../utils/sms_extractors.dart';

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

    // Computed on demand rather than cached on the model — only otp-tagged
    // messages need it, and it's a single cheap regex pass per render.
    final otpCode = message.category == SmsCategory.otp ? extractOtp(message.body) : null;

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
                    if (otpCode != null) ...[
                      const SizedBox(height: 8),
                      _CopyOtpButton(code: otpCode, outgoingTint: isOutgoing, textColor: textColor),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      Formatters.timeOfDay(message.date),
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

class _CopyOtpButton extends StatelessWidget {
  final String code;
  final bool outgoingTint;
  final Color? textColor;

  const _CopyOtpButton({required this.code, required this.outgoingTint, this.textColor});

  @override
  Widget build(BuildContext context) {
    final fg = outgoingTint ? textColor ?? Colors.white : Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied "$code"'), duration: const Duration(seconds: 1)),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: fg.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_outlined, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              'Copy $code',
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
