import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_detector.dart';
import '../../utils/message_highlighter.dart';

/// Renders [text] with any http(s)/www. links underlined and tappable
/// (opens in the device's default browser), any [highlights] bolded/
/// coloured per [highlightStyle], and everything else plain in [style].
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Ranges of [text] to visually emphasise (OTP code, transaction
  /// amount/account) — see findMessageHighlights. Empty by default so
  /// every other call site is unaffected.
  final List<TextHighlight> highlights;

  /// Per-highlight-kind style, applied to the matching substring. Required
  /// only when [highlights] is non-empty.
  final TextStyle Function(HighlightKind kind)? highlightStyle;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.linkColor,
    this.style,
    this.maxLines,
    this.overflow,
    this.highlights = const [],
    this.highlightStyle,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

/// One tagged, positioned run — either a tappable link or a styled
/// highlight — used to build the combined span sequence below.
class _Ranged {
  final int start;
  final int end;
  final TextLinkMatch? link;
  final TextHighlight? highlight;
  const _Ranged({required this.start, required this.end, this.link, this.highlight});
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final links = detectLinks(widget.text);
    if (links.isEmpty && widget.highlights.isEmpty) {
      return Text(widget.text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    }

    // Links and highlights come from unrelated patterns (a URL looks
    // nothing like an amount/account/OTP token) so in practice they never
    // overlap — sorted by start with links given priority on the rare
    // chance they do, since a broken tap target is worse than a missed bold.
    final ranges = <_Ranged>[
      for (final link in links) _Ranged(start: link.start, end: link.end, link: link),
      for (final h in widget.highlights) _Ranged(start: h.start, end: h.end, highlight: h),
    ]..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        if (byStart != 0) return byStart;
        return (a.link != null ? 0 : 1).compareTo(b.link != null ? 0 : 1);
      });

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      if (r.start < cursor) continue; // overlaps a range already emitted
      if (r.start > cursor) spans.add(TextSpan(text: widget.text.substring(cursor, r.start)));

      if (r.link != null) {
        final recognizer = TapGestureRecognizer()..onTap = () => _open(r.link!.url);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: r.link!.text,
            style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline),
            recognizer: recognizer,
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: widget.text.substring(r.start, r.end),
            style: widget.highlightStyle?.call(r.highlight!.kind),
          ),
        );
      }
      cursor = r.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No app can handle it (or the platform channel isn't wired up on
      // this build target) — nothing sensible to do beyond not crashing.
    }
  }
}
