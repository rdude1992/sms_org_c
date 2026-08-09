import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../utils/formatters.dart';
import '../utils/message_highlighter.dart';
import '../utils/sms_extractors.dart';
import 'ui/linkified_text.dart';

class MessageBubble extends StatelessWidget {
  final SmsMessage message;
  final bool selected;
  final bool selectionMode;

  /// True briefly when this bubble was jumped to (e.g. from tapping the
  /// message in the All Messages list) — draws an animated border that
  /// fades back out, so the target message is unmistakable after the scroll
  /// lands.
  final bool highlighted;

  /// Whether this message has been starred — see SmsProvider.starredMessages
  /// / the Starred screen for where it's collected across all threads.
  final bool starred;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.highlighted = false,
    this.starred = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.box == SmsBoxType.sent || message.box == SmsBoxType.outbox;
    final scheme = Theme.of(context).colorScheme;

    final bubbleColor = isOutgoing ? scheme.primary : scheme.surfaceVariant;
    final textColor = isOutgoing ? scheme.onPrimary : scheme.onSurface;

    // Computed on demand rather than cached on the model — only otp-tagged
    // messages need it, and it's a single cheap regex pass per render.
    final otpCode = message.category == SmsCategory.otp ? extractOtp(message.body) : null;

    // Same on-demand reasoning — a couple of cheap regex passes per render,
    // and only for otp/transactional messages at all (see
    // findMessageHighlights). Bolds/colours the OTP code or the amount/
    // account reference in place within the bubble text, rather than
    // requiring a tap into the message details to spot them.
    final highlights = findMessageHighlights(message.body, message.category);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? scheme.primary.withOpacity(0.14) : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Always sits at the row's leading edge (regardless of which
            // side the bubble itself hugs) so it reads the same way for
            // every row instead of jumping sides with the message
            // direction — same idea as a checkbox column in a list.
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                  size: 22,
                ),
              ),
            Expanded(
              child: Row(
                mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
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
                        border: Border.all(
                          color:
                              (highlighted || selected) ? scheme.primary : scheme.primary.withOpacity(0),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinkifiedText(
                            text: message.body,
                            style: TextStyle(color: textColor, fontSize: 15, height: 1.45),
                            // Outgoing bubbles are already primary-coloured, so a
                            // primary link colour would vanish against it —
                            // underline is the only differentiator there instead.
                            linkColor: isOutgoing ? textColor : scheme.primary,
                            highlights: highlights,
                            highlightStyle: (kind) =>
                                _highlightStyle(kind, isOutgoing: isOutgoing, textColor: textColor, scheme: scheme),
                          ),
                          if (otpCode != null) ...[
                            const SizedBox(height: 8),
                            _CopyOtpButton(code: otpCode, outgoingTint: isOutgoing, textColor: textColor),
                          ],
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Formatters.timeOfDay(message.date),
                                style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 10),
                              ),
                              if (message.simSlot != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '·',
                                  style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 10),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'SIM ${message.simSlot! + 1}',
                                  style: TextStyle(
                                    color: textColor.withOpacity(0.7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (starred) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.star, size: 11, color: Colors.amber.shade600),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Style for one highlighted run — bold throughout, plus a size bump for
  /// the OTP code and (incoming bubbles only) a credit/debit-tinted colour
  /// for the amount. Outgoing bubbles already sit on a primary-coloured
  /// background, so colouring text green/red there would clash the same
  /// way a coloured link would — bold-only carries the emphasis instead,
  /// same reasoning LinkifiedText's own linkColor already applies.
  TextStyle _highlightStyle(
    HighlightKind kind, {
    required bool isOutgoing,
    required Color textColor,
    required ColorScheme scheme,
  }) {
    switch (kind) {
      case HighlightKind.otp:
        return TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 19,
          color: isOutgoing ? textColor : scheme.primary,
        );
      case HighlightKind.creditAmount:
        return TextStyle(
          fontWeight: FontWeight.w800,
          color: isOutgoing ? textColor : const Color(0xFF10B981),
        );
      case HighlightKind.debitAmount:
        return TextStyle(
          fontWeight: FontWeight.w800,
          color: isOutgoing ? textColor : const Color(0xFFEF4444),
        );
      case HighlightKind.amount:
        return TextStyle(fontWeight: FontWeight.w800, color: textColor);
      case HighlightKind.account:
        return TextStyle(
          fontWeight: FontWeight.w700,
          color: isOutgoing ? textColor : scheme.primary,
        );
    }
  }
}

class _CopyOtpButton extends StatelessWidget {
  final String code;
  final bool outgoingTint;
  final Color textColor;

  const _CopyOtpButton({required this.code, required this.outgoingTint, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final fg = outgoingTint ? textColor : Theme.of(context).colorScheme.primary;
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
