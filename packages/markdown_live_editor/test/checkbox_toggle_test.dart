// Tests for the checkbox toggle source-mutation logic (#130).
//
// The toggle logic is a pure function: given the source text and the source
// offset of a checkbox element's start, flip the 6-char marker between
// '- [ ] ' and '- [x] '.
//
// This file tests the logic independently of the widget layer so the
// correctness invariants are verified without a widget tree.

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Toggle helper — the same logic that EditorScreen._onCheckboxToggle uses.
// Extracted here for unit testing.
// ---------------------------------------------------------------------------

/// Toggles the checkbox marker at [sourceOffset] within [source].
///
/// Returns the modified string, or [source] unchanged if the 6-char marker
/// found is not a valid checkbox marker.
///
/// [sourceOffset] is the checkbox element's own source offset — always the
/// LINE's absolute start (see md_parser.dart's checkbox branches), which for
/// a nested/indented checkbox is BEFORE the leading whitespace, not the
/// marker's own start. Any leading space/tab characters are skipped first
/// (#354) before reading the 6-char marker, so this works identically for a
/// non-nested checkbox (zero-iteration no-op) and a nested one.
///
/// Invariants:
/// - '- [ ] ' at the marker's start → '- [x] '
/// - '- [x] ' at the marker's start → '- [ ] '
/// - '- [X] ' at the marker's start → '- [ ] '  (uppercase X treated as checked)
String toggleCheckbox(String source, int sourceOffset) {
  if (sourceOffset < 0 || sourceOffset > source.length) return source;
  var markerStart = sourceOffset;
  while (markerStart < source.length &&
      (source[markerStart] == ' ' || source[markerStart] == '\t')) {
    markerStart++;
  }
  if (markerStart + 6 > source.length) return source;
  final marker = source.substring(markerStart, markerStart + 6);
  String replacement;
  if (marker == '- [ ] ') {
    replacement = '- [x] ';
  } else if (marker == '- [x] ' || marker == '- [X] ') {
    replacement = '- [ ] ';
  } else {
    return source;
  }
  return source.replaceRange(markerStart, markerStart + 6, replacement);
}

void main() {
  group('toggleCheckbox', () {
    test('- [ ] foo at offset 0 → - [x] foo', () {
      const source = '- [ ] foo';
      expect(toggleCheckbox(source, 0), '- [x] foo');
    });

    test('- [x] foo at offset 0 → - [ ] foo', () {
      const source = '- [x] foo';
      expect(toggleCheckbox(source, 0), '- [ ] foo');
    });

    test('- [X] foo at offset 0 → - [ ] foo (uppercase X treated as checked)',
        () {
      const source = '- [X] foo';
      expect(toggleCheckbox(source, 0), '- [ ] foo');
    });

    test('toggle at non-zero offset works correctly', () {
      // source = 'intro\n- [ ] task'
      // checkbox starts at offset 6
      const source = 'intro\n- [ ] task';
      expect(toggleCheckbox(source, 6), 'intro\n- [x] task');
    });

    test('bounds check: sourceOffset + 6 > source.length → source unchanged',
        () {
      const source = '- [ ]'; // only 5 chars — too short
      expect(toggleCheckbox(source, 0), source);
    });

    test('non-checkbox content → source unchanged', () {
      const source = '- item';
      expect(toggleCheckbox(source, 0), source);
    });

    test('second checkbox in multi-line source toggles correctly', () {
      // '- [ ] one\n- [x] two' — second line starts at offset 10
      const source = '- [ ] one\n- [x] two';
      expect(toggleCheckbox(source, 10), '- [ ] one\n- [ ] two');
    });

    test('toggle is unaffected by inline-formatted content after the marker',
        () {
      // ADR-33 Stage 2: content after '- [ ] ' now flows through the inline
      // engine, but toggling only rewrites the 6-char marker prefix — the
      // formatted remainder ('**urgent** call back') is preserved verbatim.
      const source = '- [ ] **urgent** call back';
      expect(toggleCheckbox(source, 0), '- [x] **urgent** call back');
      // And back again.
      const checked = '- [x] **urgent** call back';
      expect(toggleCheckbox(checked, 0), '- [ ] **urgent** call back');
    });
  });

  group('toggleCheckbox — nested/indented checkboxes (#354)', () {
    test(
        'a nested checkbox toggles correctly when sourceOffset is the '
        'LINE\'s absolute start (before the leading whitespace) — the exact '
        'offset checkboxSourceOffsetForTap() resolves to, per '
        'md_parser.dart\'s indented-checkbox branch (start: lineStart)', () {
      // '  - [ ] Nested task' — sourceOffset 0 is the first leading space,
      // NOT the '-' at offset 2. Before the #354 fix this returned `source`
      // unchanged, since substring(0, 6) read '  - [ ' (two leading spaces
      // + a partial marker), which matches neither '- [ ] ' nor '- [x] '.
      const source = '  - [ ] Nested task';
      expect(toggleCheckbox(source, 0), '  - [x] Nested task');
    });

    test('a checked nested checkbox toggles back to unchecked', () {
      const source = '  - [x] Nested task';
      expect(toggleCheckbox(source, 0), '  - [ ] Nested task');
    });

    test('a tab-indented checkbox toggles correctly (tabs, not just spaces)',
        () {
      const source = '\t- [ ] Nested task';
      expect(toggleCheckbox(source, 0), '\t- [x] Nested task');
    });

    test('a deeply-nested (2-level) checkbox toggles correctly', () {
      const source = '    - [ ] Deeply nested task';
      expect(toggleCheckbox(source, 0), '    - [x] Deeply nested task');
    });

    test(
        'a nested checkbox on a non-zero-offset line toggles correctly — '
        'combines the leading-whitespace skip with a non-zero sourceOffset',
        () {
      // 'Parent\n  - [ ] task' — the nested checkbox's line starts at
      // offset 7 (just past 'Parent\n'), and its own leading whitespace
      // starts there too.
      const source = 'Parent\n  - [ ] task';
      expect(toggleCheckbox(source, 7), 'Parent\n  - [x] task');
    });

    test(
        'a nested line that is NOT actually a checkbox (whitespace-skip '
        'lands on ordinary indented text) is left unchanged', () {
      const source = '  not a checkbox line';
      expect(toggleCheckbox(source, 0), source);
    });

    test(
        'bounds check still applies after skipping whitespace: an indented '
        'marker too short to contain a full 6-char marker is left unchanged',
        () {
      const source = '  - [ ]'; // whitespace + 5 chars — too short overall
      expect(toggleCheckbox(source, 0), source);
    });
  });
}
