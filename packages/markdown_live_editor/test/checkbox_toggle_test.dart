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
/// at [sourceOffset] is not a valid checkbox marker.
///
/// Invariants:
/// - '- [ ] ' at [sourceOffset] → '- [x] '
/// - '- [x] ' at [sourceOffset] → '- [ ] '
/// - '- [X] ' at [sourceOffset] → '- [ ] '  (uppercase X treated as checked)
String toggleCheckbox(String source, int sourceOffset) {
  if (sourceOffset < 0 || sourceOffset + 6 > source.length) return source;
  final marker = source.substring(sourceOffset, sourceOffset + 6);
  String replacement;
  if (marker == '- [ ] ') {
    replacement = '- [x] ';
  } else if (marker == '- [x] ' || marker == '- [X] ') {
    replacement = '- [ ] ';
  } else {
    return source;
  }
  return source.replaceRange(sourceOffset, sourceOffset + 6, replacement);
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
  });
}
