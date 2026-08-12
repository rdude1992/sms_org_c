import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/category.dart';
import '../models/sms_message.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/message_highlighter.dart';
import '../utils/sms_extractors.dart';
import 'category_badge.dart';
import 'sim_picker.dart' show simColor;
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

  /// True the first time this bubble is built for a message ThreadScreen
  /// hasn't seen before (a fresh send, or one that just arrived) — plays a
  /// one-shot fade/slide-in (see [_BubbleEntrance]) instead of the plain
  /// static render every other bubble gets. Never toggles back to false for
  /// the same message, so scrolling it in and out of view again doesn't
  /// replay the animation.
  final bool isNew;

  /// Retries a message whose [SmsMessage.sendState] is
  /// [OutgoingSendState.failed] — wired to the status indicator's tap
  /// target below. Null (no retry offered) for every other state,
  /// including [OutgoingSendState.notDelivered] — see SmsProvider.retrySend
  /// for why that one's excluded.
  final VoidCallback? onRetry;

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
    this.isNew = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.box == SmsBoxType.sent || message.box == SmsBoxType.outbox;
    final scheme = Theme.of(context).colorScheme;

    // Sent bubbles get their own fixed dark-neutral look — deliberately
    // independent of both light/dark theme and the terracotta brand accent,
    // the same way a chat app's own sent-bubble color usually stays fixed
    // regardless of system theme, rather than the accent-tinted bubble this
    // used to be.
    final bubbleColor = isOutgoing ? AppColors.stone900 : scheme.surfaceVariant;
    final textColor = isOutgoing ? AppColors.darkOnSurface : scheme.onSurface;

    // Computed on demand rather than cached on the model — only otp-tagged
    // messages need it, and it's a single cheap regex pass per render.
    final otpCode = message.category == SmsCategory.otp ? extractOtp(message.body) : null;

    // Same on-demand reasoning — a couple of cheap regex passes per render,
    // and only for otp/transactional messages at all (see
    // findMessageHighlights). Bolds/colours the OTP code or the amount/
    // account reference in place within the bubble text, rather than
    // requiring a tap into the message details to spot them.
    final highlights = findMessageHighlights(message.body, message.category);
    final sendState = message.sendState;

    final bubble = GestureDetector(
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
                          const SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CategoryBadge(category: message.category, compact: true, showLabel: false),
                              const SizedBox(width: 6),
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
                                // Same per-slot colour as SimPicker, so which
                                // line a message went out/came in on reads
                                // consistently between the picker and the
                                // thread itself.
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: simColor(message.simSlot!),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
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
                              if (isOutgoing && sendState != null) ...[
                                const SizedBox(width: 6),
                                _SendStatusIndicator(
                                  state: sendState,
                                  textColor: textColor,
                                  scheme: scheme,
                                  onRetry: onRetry,
                                ),
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

    // Only the freshly-appeared bubble pays for an AnimationController —
    // every other bubble in a long thread renders exactly as before.
    return isNew ? _BubbleEntrance(child: bubble) : bubble;
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

/// One-shot fade + slide-up entrance for a bubble ThreadScreen has just
/// decided is new (see MessageBubble.isNew) — plays once via its own
/// AnimationController rather than TweenAnimationBuilder, so a provider-
/// driven rebuild while the message is still "new" (e.g. its send status
/// flipping from sending to sent moments later) can't accidentally
/// re-trigger it.
class _BubbleEntrance extends StatefulWidget {
  final Widget child;
  const _BubbleEntrance({required this.child});

  @override
  State<_BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<_BubbleEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final Animation<double> _curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(_curved),
        child: widget.child,
      ),
    );
  }
}

/// Trailing status glyph for an outgoing bubble — a small spinner while
/// [OutgoingSendState.sending], a single check once [OutgoingSendState.sent],
/// a double check once [OutgoingSendState.delivered], and an error glyph
/// (tappable to retry when [onRetry] is set) for [OutgoingSendState.failed]
/// / [OutgoingSendState.notDelivered].
class _SendStatusIndicator extends StatelessWidget {
  final OutgoingSendState state;
  final Color textColor;
  final ColorScheme scheme;
  final VoidCallback? onRetry;

  const _SendStatusIndicator({
    required this.state,
    required this.textColor,
    required this.scheme,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case OutgoingSendState.sending:
        return Tooltip(
          message: 'Sending…',
          child: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: textColor.withOpacity(0.7)),
          ),
        );
      case OutgoingSendState.sent:
        return Tooltip(
          message: 'Sent',
          child: Icon(Icons.done, size: 13, color: textColor.withOpacity(0.7)),
        );
      case OutgoingSendState.delivered:
        return Tooltip(
          message: 'Delivered',
          child: Icon(Icons.done_all, size: 13, color: textColor.withOpacity(0.7)),
        );
      case OutgoingSendState.notDelivered:
        return Tooltip(
          message: 'Not delivered',
          child: Icon(Icons.error_outline, size: 13, color: scheme.error),
        );
      case OutgoingSendState.failed:
        return InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 13, color: scheme.error),
              const SizedBox(width: 3),
              Text(
                'Failed · Retry',
                style: TextStyle(fontSize: 10, color: scheme.error, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
    }
  }
}
