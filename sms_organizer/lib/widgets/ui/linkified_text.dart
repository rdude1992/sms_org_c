import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_detector.dart';

/// Renders [text] with any http(s)/www. links underlined and tappable
/// (opens in the device's default browser) — everything else renders
/// plain in [style].
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText({
    super.key,
    required this.text,
    required this.linkColor,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
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
    if (links.isEmpty) {
      return Text(widget.text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(link.url);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: link.text,
          style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline),
          recognizer: recognizer,
        ),
      );
      cursor = link.end;
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
