class BlockSplitter {
  BlockSplitter._();

  static final _orderedRe = RegExp(r'^(\d+)\. ');
  static final _taskPrefixRe = RegExp(r'^(- \[[ x]\] )');
  static final _unorderedPrefixRe = RegExp(r'^([-*] )');

  /// Splits [markdown] into blocks — one block per physical line.
  ///
  /// `split('')` → `['']`. Round-trips perfectly with [join].
  static List<String> split(String markdown) {
    if (markdown.isEmpty) return [''];
    return markdown.split('\n');
  }

  /// Joins [blocks] back into a markdown string with `\n` between blocks.
  static String join(List<String> blocks) => blocks.join('\n');

  /// Returns the list continuation prefix for [line], or null if [line] is not
  /// a list item. Used by both the editor and individual blocks for
  /// auto-continue on Enter.
  static String? listContinuation(String line) {
    final task = _taskPrefixRe.firstMatch(line);
    if (task != null) return '- [ ] ';

    final unordered = _unorderedPrefixRe.firstMatch(line);
    if (unordered != null) return unordered.group(1)!;

    final ordered = _orderedRe.firstMatch(line);
    if (ordered != null) {
      final n = int.parse(ordered.group(1)!);
      return '${n + 1}. ';
    }

    return null;
  }
}
