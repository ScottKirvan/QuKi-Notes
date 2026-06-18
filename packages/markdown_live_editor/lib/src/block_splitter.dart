class BlockSplitter {
  BlockSplitter._();

  static final _listLineRe = RegExp(r'^\s*([-*]|\d+\.)\s');
  static final _taskLineRe = RegExp(r'^\s*- \[[ x]\] ');
  static final _headingRe = RegExp(r'^#{1,6} ');
  static final _orderedRe = RegExp(r'^(\d+)\. ');
  static final _taskPrefixRe = RegExp(r'^(- \[[ x]\] )');
  static final _unorderedPrefixRe = RegExp(r'^([-*] )');

  static bool _isList(String line) =>
      _listLineRe.hasMatch(line) || _taskLineRe.hasMatch(line);

  static bool _isHeading(String line) => _headingRe.hasMatch(line);

  /// Splits [markdown] into logical blocks.
  ///
  /// Rules:
  /// - Blank lines (`\n\n`) normally separate blocks.
  /// - Headings always start their own block even without a blank line.
  /// - Contiguous list lines (unordered, ordered, task) are grouped into one
  ///   block regardless of blank lines between them.
  /// - `split('')` → `['']`.
  static List<String> split(String markdown) {
    if (markdown.isEmpty) return [''];

    final lines = markdown.split('\n');
    final blocks = <String>[];
    final current = <String>[];
    var inList = false;
    var pendingBlanks = 0;

    void flush() {
      while (current.isNotEmpty && current.last.isEmpty) {
        current.removeLast();
      }
      if (current.isNotEmpty) blocks.add(current.join('\n'));
      current.clear();
      inList = false;
      pendingBlanks = 0;
    }

    for (final line in lines) {
      if (line.isEmpty) {
        pendingBlanks++;
        continue;
      }

      if (_isHeading(line)) {
        flush();
        blocks.add(line);
        continue;
      }

      final lineIsList = _isList(line);

      if (pendingBlanks > 0) {
        if (inList && lineIsList) {
          // Both sides are list lines — keep in the same block, preserving blanks.
          for (var i = 0; i < pendingBlanks; i++) {
            current.add('');
          }
        } else {
          flush();
        }
        pendingBlanks = 0;
      }

      current.add(line);
      inList = lineIsList;
    }

    flush();
    return blocks.isEmpty ? [''] : blocks;
  }

  /// Joins [blocks] back into a markdown string with `\n\n` between blocks.
  static String join(List<String> blocks) => blocks.join('\n\n');

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
