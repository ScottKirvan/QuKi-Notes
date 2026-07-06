import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

void main() {
  group('MdParser.parse', () {
    test('empty string → empty list', () {
      expect(MdParser.parse(''), isEmpty);
    });

    test('plain text → empty list', () {
      expect(MdParser.parse('hello world'), isEmpty);
    });

    test('"# Hello" → [h1(0, 7)]', () {
      final els = MdParser.parse('# Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h1);
      expect(els[0].start, 0);
      expect(els[0].end, 7);
    });

    test('"## Hello" → [h2(0, 8)]', () {
      final els = MdParser.parse('## Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h2);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"### Hello" → [h3(0, 9)]', () {
      final els = MdParser.parse('### Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h3);
      expect(els[0].start, 0);
      expect(els[0].end, 9);
    });

    test('"**bold**" → [bold(0, 8)]', () {
      final els = MdParser.parse('**bold**');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.bold);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"*italic*" → [italic(0, 8)]', () {
      final els = MdParser.parse('*italic*');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.italic);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"__bold__" → [bold(0, 8)]', () {
      final els = MdParser.parse('__bold__');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.bold);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"_italic_" → [italic(0, 8)]', () {
      final els = MdParser.parse('_italic_');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.italic);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"hello **world** there" → [bold(6, 15)]', () {
      final els = MdParser.parse('hello **world** there');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.bold);
      expect(els[0].start, 6);
      expect(els[0].end, 15);
    });

    test('"*one* and **two**" → [italic(0, 5), bold(10, 17)]', () {
      final els = MdParser.parse('*one* and **two**');
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.italic);
      expect(els[0].start, 0);
      expect(els[0].end, 5);
      expect(els[1].kind, MdElKind.bold);
      expect(els[1].start, 10);
      expect(els[1].end, 17);
    });

    test('"# Heading\\n**bold**" → [h1(0, 9), bold(10, 18)]', () {
      final els = MdParser.parse('# Heading\n**bold**');
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.h1);
      expect(els[0].start, 0);
      expect(els[0].end, 9);
      expect(els[1].kind, MdElKind.bold);
      expect(els[1].start, 10);
      expect(els[1].end, 18);
    });

    test('"****" → [] (empty bold content not emitted)', () {
      expect(MdParser.parse('****'), isEmpty);
    });

    test('"**no close" → [] (no matching close delimiter)', () {
      expect(MdParser.parse('**no close'), isEmpty);
    });

    test('"**crosses\\nlines**" → [] (no cross-line matching)', () {
      expect(MdParser.parse('**crosses\nlines**'), isEmpty);
    });

    test('"# H\\nnext line" → [h1(0, 3)] (only heading line)', () {
      final els = MdParser.parse('# H\nnext line');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h1);
      expect(els[0].start, 0);
      expect(els[0].end, 3);
    });

    test('"#notaheading" → [] (# without trailing space)', () {
      expect(MdParser.parse('#notaheading'), isEmpty);
    });

    test('"not # heading" → [] (# not at line start)', () {
      expect(MdParser.parse('not # heading'), isEmpty);
    });

    // MdElement helpers
    test(
        'MdElement.isDelimiter: bold(0,8) → si=0 true, si=1 true, si=2 false, si=6 true, si=7 true',
        () {
      final el = MdElement(kind: MdElKind.bold, start: 0, end: 8);
      expect(el.isDelimiter(0), isTrue);
      expect(el.isDelimiter(1), isTrue);
      expect(el.isDelimiter(2), isFalse);
      expect(el.isDelimiter(6), isTrue);
      expect(el.isDelimiter(7), isTrue);
    });

    test('MdElement.isDelimiter: h1(0,7) → si=0 true, si=1 true, si=2 false',
        () {
      final el = MdElement(kind: MdElKind.h1, start: 0, end: 7);
      expect(el.isDelimiter(0), isTrue);
      expect(el.isDelimiter(1), isTrue);
      expect(el.isDelimiter(2), isFalse);
    });

    test(
        'MdElement.containsOffset: bold(6,15) → 5 false, 6 true, 14 true, 15 false',
        () {
      final el = MdElement(kind: MdElKind.bold, start: 6, end: 15);
      expect(el.containsOffset(5), isFalse);
      expect(el.containsOffset(6), isTrue);
      expect(el.containsOffset(14), isTrue);
      expect(el.containsOffset(15), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 4 — list element tests
  // ---------------------------------------------------------------------------

  group('MdParser.parse — list elements', () {
    test('"- item" → [ul(0, 6)]', () {
      final els = MdParser.parse('- item');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ul);
      expect(els[0].start, 0);
      expect(els[0].end, 6);
    });

    test('"* item" → [ul(0, 6)] (* prefix)', () {
      final els = MdParser.parse('* item');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ul);
      expect(els[0].start, 0);
      expect(els[0].end, 6);
    });

    test('"+ item" → [ul(0, 6)] (+ prefix)', () {
      final els = MdParser.parse('+ item');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ul);
      expect(els[0].start, 0);
      expect(els[0].end, 6);
    });

    test('"- [ ] task" → [checkboxUnchecked(0, 10)]', () {
      final els = MdParser.parse('- [ ] task');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.checkboxUnchecked);
      expect(els[0].start, 0);
      expect(els[0].end, 10);
    });

    test('"- [x] done" → [checkboxChecked(0, 10)] (lowercase x)', () {
      final els = MdParser.parse('- [x] done');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.checkboxChecked);
      expect(els[0].start, 0);
      expect(els[0].end, 10);
    });

    test('"- [X] done" → [checkboxChecked(0, 10)] (uppercase X)', () {
      final els = MdParser.parse('- [X] done');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.checkboxChecked);
      expect(els[0].start, 0);
      expect(els[0].end, 10);
    });

    test(
        'checkbox has priority over ul: "- [ ] " detected as checkboxUnchecked not ul',
        () {
      final els = MdParser.parse('- [ ] task');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.checkboxUnchecked);
    });

    test('"- [x] done" detected as checkboxChecked not ul', () {
      final els = MdParser.parse('- [x] done');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.checkboxChecked);
    });

    test('"1. first" → [ol(0, 8)] with seqNum=1 (source digit)', () {
      final els = MdParser.parse('1. first');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ol);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
      expect(els[0].seqNum, 1);
    });

    test(
        'ol seqNum is block-relative: consecutive ol lines increment regardless of source digit',
        () {
      // Source digits 1, 3, 5 — but they form one consecutive block, so
      // block starts at 1 and each line increments by 1: rendered as 1, 2, 3.
      const source = '1. first\n3. second\n5. third';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].kind, MdElKind.ol);
      expect(els[0].seqNum, 1);
      expect(els[1].kind, MdElKind.ol);
      expect(els[1].seqNum, 2);
      expect(els[2].kind, MdElKind.ol);
      expect(els[2].seqNum, 3);
    });

    test('ol common shorthand: "1. 1. 1." → block-relative seqNums 1, 2, 3',
        () {
      // GFM-compatible: repeating "1." is the common shorthand for numbered lists.
      const source = '1. first\n1. second\n1. third';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].seqNum, 1);
      expect(els[1].seqNum, 2);
      expect(els[2].seqNum, 3);
    });

    test('ol block starting at 5: "5. 1. 1." → seqNums 5, 6, 7', () {
      // Block anchors to first line's source digit (5); subsequent lines increment.
      const source = '5. first\n1. second\n1. third';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].seqNum, 5);
      expect(els[1].seqNum, 6);
      expect(els[2].seqNum, 7);
    });

    test('ol two separate blocks: "1. a\\nplain\\n7. b" → seqNums 1, 7', () {
      // Plain line resets the block; second block starts at its own source digit.
      const source = '1. a\nplain line\n7. b';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].seqNum, 1);
      expect(els[1].seqNum, 7);
    });

    test('non-1 source digit: "5. item" → seqNum == 5', () {
      final els = MdParser.parse('5. item');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ol);
      expect(els[0].seqNum, 5);
      expect(els[0].collapsedMarker, '5. ');
    });

    test(
        'ol two separate blocks: "1. first\\n2. second\\nplain\\n7. restart" → seqNums 1, 2, 7',
        () {
      // Block 1: '1. first' (start=1, run=1 → seqNum 1), '2. second' (start=1, run=2 → seqNum 2).
      // Plain line resets the block counter.
      // Block 2: '7. restart' (start=7, run=1 → seqNum 7).
      const source = '1. first\n2. second\nplain line\n7. restart';
      final els = MdParser.parse(source);
      // Two ol elements, one plain line (no element), one ol.
      expect(els, hasLength(3));
      expect(els[0].kind, MdElKind.ol);
      expect(els[0].seqNum, 1);
      expect(els[1].kind, MdElKind.ol);
      expect(els[1].seqNum, 2);
      expect(els[2].kind, MdElKind.ol);
      expect(els[2].seqNum, 7); // second block starts at its own source digit
    });

    test('heading followed by a list line produces two separate elements', () {
      const source = '# Title\n- item';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.h1);
      expect(els[0].start, 0);
      expect(els[0].end, 7);
      expect(els[1].kind, MdElKind.ul);
      expect(els[1].start, 8);
      expect(els[1].end, 14);
    });

    test('ol delimiter chars are isDelimiter; source digits count correctly',
        () {
      // '1. item' — source delimiter '1. ' = 3 chars (indices 0,1,2).
      final els = MdParser.parse('1. item');
      expect(els, hasLength(1));
      final el = els[0];
      expect(el.kind, MdElKind.ol);
      expect(el.openDelimLen, 3); // '1. ' = digits(1) + '. ' (2)
      expect(el.isDelimiter(0), isTrue); // '1'
      expect(el.isDelimiter(1), isTrue); // '.'
      expect(el.isDelimiter(2), isTrue); // ' '
      expect(el.isDelimiter(3), isFalse); // 'i' (content)
    });

    test('two-digit ol: "12. item" has openDelimLen 4', () {
      // '12. item' — delimiter '12. ' = 4 chars.
      final els = MdParser.parse('12. item');
      expect(els, hasLength(1));
      expect(els[0].openDelimLen, 4);
    });

    test('ul openDelimLen = 2, isDelimiter correct', () {
      final el = MdElement(kind: MdElKind.ul, start: 0, end: 6);
      expect(el.openDelimLen, 2);
      expect(el.isDelimiter(0), isTrue); // '-'
      expect(el.isDelimiter(1), isTrue); // ' '
      expect(el.isDelimiter(2), isFalse); // content
    });

    test('checkboxUnchecked openDelimLen = 6, isDelimiter correct', () {
      final el = MdElement(kind: MdElKind.checkboxUnchecked, start: 0, end: 10);
      expect(el.openDelimLen, 6);
      for (var i = 0; i < 6; i++) {
        expect(el.isDelimiter(i), isTrue,
            reason: 'index $i should be delimiter');
      }
      expect(el.isDelimiter(6), isFalse);
    });

    test('collapsedMarker for ul = "• "', () {
      final el = MdElement(kind: MdElKind.ul, start: 0, end: 6);
      expect(el.collapsedMarker, '• ');
    });

    test('collapsedMarker for checkboxUnchecked = "☐ "', () {
      final el = MdElement(kind: MdElKind.checkboxUnchecked, start: 0, end: 10);
      expect(el.collapsedMarker, '☐ ');
    });

    test('collapsedMarker for checkboxChecked = "☑ "', () {
      final el = MdElement(kind: MdElKind.checkboxChecked, start: 0, end: 10);
      expect(el.collapsedMarker, '☑ ');
    });

    test('collapsedMarker for ol with seqNum=3 = "3. "', () {
      final el = MdElement(
        kind: MdElKind.ol,
        start: 0,
        end: 8,
        seqNum: 3,
        srcOlDelimLen: 3,
      );
      expect(el.collapsedMarker, '3. ');
    });
  });
}
