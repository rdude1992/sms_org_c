/// Detects http(s):// and bare "www." links within message text, for
/// making them tappable in the thread view. Deliberately conservative
/// (requires an explicit scheme or a leading "www.") rather than guessing
/// at bare domains like "amazon.in" — those are indistinguishable from
/// ordinary words without a much heavier heuristic, and a missed link is
/// a lot safer than turning random text into a bogus one.
final _linkRegex = RegExp(
  r'(https?://[^\s<>"]+)|(www\.[^\s<>"]+)',
  caseSensitive: false,
);

const _trailingPunctuation = {'.', ',', '!', '?', ')', ']', '}', ':', ';', '"', "'"};

class TextLinkMatch {
  final int start;
  final int end;
  final String text;

  const TextLinkMatch({required this.start, required this.end, required this.text});

  /// The URL to actually launch — a "www."-only match needs a scheme
  /// prefixed, since neither url_launcher nor the browser it hands off to
  /// will infer one.
  String get url => text.toLowerCase().startsWith('http') ? text : 'https://$text';
}

/// Finds every link in [text], trimming trailing punctuation that reads as
/// sentence structure rather than part of the URL itself (e.g. the
/// period in "check example.com." or the closing paren in "(example.com)").
List<TextLinkMatch> detectLinks(String text) {
  final matches = <TextLinkMatch>[];
  for (final m in _linkRegex.allMatches(text)) {
    var end = m.end;
    while (end > m.start && _trailingPunctuation.contains(text[end - 1])) {
      end--;
    }
    if (end <= m.start) continue;
    matches.add(TextLinkMatch(start: m.start, end: end, text: text.substring(m.start, end)));
  }
  return matches;
}
