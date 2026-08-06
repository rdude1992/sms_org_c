import 'package:flutter/widgets.dart';

/// Builds a short, match-centered preview of search results — a plain
/// `Text(body, maxLines: 1)` truncates from the start, which can crop the
/// actual match out of view entirely when it's deep into a long message.
class SearchSnippet {
  /// Returns spans of [text] centered on the first case-insensitive
  /// occurrence of [query], with ellipses where truncated and the match
  /// itself styled with [matchStyle]. Falls back to the untouched start of
  /// [text] if [query] isn't found in it at all (e.g. this row matched on
  /// sender name/address rather than the message body).
  static List<InlineSpan> build(
    String text,
    String query, {
    required TextStyle baseStyle,
    required TextStyle matchStyle,
    int contextChars = 30,
  }) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [TextSpan(text: text, style: baseStyle)];

    final idx = text.toLowerCase().indexOf(trimmedQuery.toLowerCase());
    if (idx == -1) return [TextSpan(text: text, style: baseStyle)];

    final matchEnd = idx + trimmedQuery.length;
    final start = (idx - contextChars).clamp(0, text.length);
    final end = (matchEnd + contextChars).clamp(0, text.length);

    final prefix = '${start > 0 ? '…' : ''}${text.substring(start, idx)}';
    final match = text.substring(idx, matchEnd);
    final suffix = '${text.substring(matchEnd, end)}${end < text.length ? '…' : ''}';

    return [
      TextSpan(text: prefix, style: baseStyle),
      TextSpan(text: match, style: matchStyle),
      TextSpan(text: suffix, style: baseStyle),
    ];
  }
}

/// Single-line preview text for a search result row: a plain [Text] when
/// [query] is blank, or a match-highlighted [SearchSnippet] when it isn't.
class SearchPreviewText extends StatelessWidget {
  final String body;
  final String query;
  final TextStyle baseStyle;
  final Color matchColor;

  const SearchPreviewText({
    super.key,
    required this.body,
    required this.query,
    required this.baseStyle,
    required this.matchColor,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return Text(body, maxLines: 1, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    return Text.rich(
      TextSpan(
        children: SearchSnippet.build(
          body,
          trimmedQuery,
          baseStyle: baseStyle,
          matchStyle: baseStyle.copyWith(
            color: matchColor,
            fontWeight: FontWeight.bold,
            backgroundColor: matchColor.withOpacity(0.12),
          ),
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
