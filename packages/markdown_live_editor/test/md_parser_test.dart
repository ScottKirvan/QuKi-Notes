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

  // ---------------------------------------------------------------------------
  // Stage 5 — image element tests
  // ---------------------------------------------------------------------------

  group('MdParser.parse — image elements', () {
    test('"![alt](path)" on its own line → image with correct imagePath', () {
      final els = MdParser.parse('![alt](../images/photo.jpg)');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
      expect(els[0].start, 0);
      expect(els[0].end, 27);
      expect(els[0].imagePath, '../images/photo.jpg');
    });

    test('"![](path)" (empty alt) parses correctly', () {
      final els = MdParser.parse('![](foo.png)');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
      expect(els[0].imagePath, 'foo.png');
    });

    test('inline image within surrounding text is NOT parsed as block image',
        () {
      // A line with other content before or after must not become an image element.
      final els = MdParser.parse('some text ![alt](path) more');
      expect(els, isEmpty,
          reason: 'block-image detection requires the entire line to be ![]()');
    });

    test('malformed line starting with "![" but no closing ")" → not image',
        () {
      final els = MdParser.parse('![alt](path');
      expect(els, isEmpty,
          reason: 'line must end with ")" to qualify as block image');
    });

    test(
        'image openDelimLen equals full line length (entire line is delimiter)',
        () {
      const source = '![alt](img.png)';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      final el = els[0];
      expect(el.kind, MdElKind.image);
      expect(el.openDelimLen, source.length);
    });

    test('image closeDelimLen is 0', () {
      final el = MdParser.parse('![x](y.jpg)').first;
      expect(el.closeDelimLen, 0);
    });

    test('image collapsedMarker is empty string', () {
      final el = MdParser.parse('![x](y.jpg)').first;
      expect(el.collapsedMarker, '');
    });

    test('all chars in image element are delimiters (isDelimiter)', () {
      const source = '![alt](p.png)';
      final el = MdParser.parse(source).first;
      for (var i = 0; i < source.length; i++) {
        expect(el.isDelimiter(i), isTrue,
            reason: 'source[$i] should be a delimiter for image element');
      }
    });

    test('image element in multi-line source has correct start/end', () {
      const source = 'first line\n![alt](img.jpg)\nlast line';
      final els = MdParser.parse(source);
      // Only the image line should produce an element.
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
      // 'first line\n' = 11 chars → image starts at 11.
      expect(els[0].start, 11);
      expect(els[0].end, 11 + '![alt](img.jpg)'.length);
      expect(els[0].imagePath, 'img.jpg');
    });

    test('imagePath is empty string for non-image elements', () {
      final els = MdParser.parse('# Heading');
      expect(els, hasLength(1));
      expect(els[0].imagePath, '');
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 6 — link element tests
  // ---------------------------------------------------------------------------

  group('MdParser.parse — link elements', () {
    test('"[text](url)" → one link element covering the full pattern', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.link);
      // start = index of '[', end = index of ')' + 1
      expect(els[0].start, 0);
      expect(els[0].end, source.length);
    });

    test('url extracted correctly from "[Go](https://go.dev)"', () {
      final els = MdParser.parse('[Go](https://go.dev)');
      expect(els, hasLength(1));
      expect(els[0].url, 'https://go.dev');
    });

    test('"![alt](url)" not parsed as link — image not link', () {
      final els = MdParser.parse('![alt](https://example.com)');
      // The whole line is a block image, not a link.
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
    });

    test('"[a](b) and [c](d)" → two link elements, non-overlapping', () {
      const source = '[a](b) and [c](d)';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.link);
      expect(els[0].start, 0);
      expect(els[0].end, 6); // '[a](b)' = 6 chars
      expect(els[0].url, 'b');
      expect(els[1].kind, MdElKind.link);
      expect(els[1].start, 11);
      expect(els[1].end, 17); // '[c](d)' = 6 chars at offset 11
      expect(els[1].url, 'd');
    });

    test('cross-line "[text\\n](url)" → no link element', () {
      // '[' and ')' not on the same line — no link.
      final els = MdParser.parse('[text\n](url)');
      expect(els.where((e) => e.kind == MdElKind.link), isEmpty);
    });

    test('"[]()" → link element with empty text and empty url', () {
      final els = MdParser.parse('[]()');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.link);
      expect(els[0].url, '');
      expect(els[0].start, 0);
      expect(els[0].end, 4);
    });

    test('"[no close url" → no link element (missing closing paren)', () {
      final els = MdParser.parse('[no close url');
      expect(els.where((e) => e.kind == MdElKind.link), isEmpty);
    });

    test(
        'link element with text adjacent to bold: "[**b**](url)" → 1 link only',
        () {
      // Bold inside link text is not separately parsed — link takes priority
      // since it is checked first in the inline scan.
      const source = '[**b**](url)';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.link);
      expect(els[0].url, 'url');
    });

    test('link openDelimLen = 1 (the "[" char)', () {
      final els = MdParser.parse('[hi](http://x.com)');
      expect(els, hasLength(1));
      expect(els[0].openDelimLen, 1);
    });

    test('link closeDelimLen = 2 + url.length + 1', () {
      // url = 'http://x.com' (12 chars), closeDelimLen = 2 + 12 + 1 = 15
      final els = MdParser.parse('[hi](http://x.com)');
      expect(els, hasLength(1));
      final url = els[0].url;
      expect(els[0].closeDelimLen, 2 + url.length + 1);
    });

    test(
        'link isDelimiter: "[" is opening delim, "](...)" chars are closing delim',
        () {
      // source = '[Go](https://go.dev)'
      // start=0, end=20, openDelimLen=1, closeDelimLen=2+14+1=17
      // content 'Go' at offsets 1..2 (not delimiters)
      // closing delimiter starts at end - closeDelimLen = 20 - 17 = 3
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      final el = els[0];
      expect(el.isDelimiter(0), isTrue, reason: '"[" is delimiter');
      expect(el.isDelimiter(1), isFalse, reason: '"G" is content');
      expect(el.isDelimiter(2), isFalse, reason: '"o" is content');
      expect(el.isDelimiter(3), isTrue, reason: '"]" starts closing delim');
      expect(el.isDelimiter(19), isTrue, reason: '")" ends closing delim');
    });

    test('link url field is empty for non-link elements', () {
      final els = MdParser.parse('**bold**');
      expect(els, hasLength(1));
      expect(els[0].url, '');
    });

    test('link in a line with surrounding plain text', () {
      const source = 'visit [Go](https://go.dev) now';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.link);
      // '[Go](https://go.dev)' starts at offset 6.
      expect(els[0].start, 6);
      expect(els[0].end, 6 + '[Go](https://go.dev)'.length);
      expect(els[0].url, 'https://go.dev');
    });

    test('link on a heading line is NOT parsed (headings skip inline scan)',
        () {
      // Headings are handled before the inline scan; links inside headings
      // are not recognized in the current parser.
      final els = MdParser.parse('# See [Go](https://go.dev)');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h1);
    });
  });

  // ---------------------------------------------------------------------------
  // Bug #219 — unmatched '**' / '__' must not fall through to italic check
  // ---------------------------------------------------------------------------

  group('MdParser.parse — unmatched bold delimiter fallthrough (bug #219)', () {
    test('unmatched "**" alone → no elements — regression: bug #219', () {
      // '**' with no close: both chars are literal, no element emitted.
      expect(MdParser.parse('**'), isEmpty);
    });

    test(
        'unmatched "**" with plain text after → no elements — regression: bug #219',
        () {
      // '**word': no matching close '**', so both '*' chars are literal.
      expect(MdParser.parse('**word'), isEmpty);
    });

    test(
        'unmatched "**" before a valid "*italic*" → only one italic element — regression: bug #219',
        () {
      // '**hello *world*': the leading '**' has no close '**'.
      // Neither of the two '*' chars in '**' should be reused as an italic opener.
      // The only element is the correctly matched '*world*' at offset 8–15.
      const source = '**hello *world*';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.italic);
      expect(els[0].start, 8); // '*' in '*world*'
      expect(els[0].end, 15); // closing '*' + 1
    });

    test('unmatched "__" alone → no elements — regression: bug #219', () {
      expect(MdParser.parse('__'), isEmpty);
    });

    test(
        'unmatched "__" with plain text after → no elements — regression: bug #219',
        () {
      expect(MdParser.parse('__word'), isEmpty);
    });

    test(
        'unmatched "__" before a valid "_italic_" → only one italic element — regression: bug #219',
        () {
      // '__hello _world_': the leading '__' has no close '__'.
      // The only element is the correctly matched '_world_' at offset 8–15.
      const source = '__hello _world_';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.italic);
      expect(els[0].start, 8); // '_' in '_world_'
      expect(els[0].end, 15); // closing '_' + 1
    });

    test('matched "**word**" still produces bold element — regression guard',
        () {
      final els = MdParser.parse('**word**');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.bold);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test(
        'unmatched "**" on same line as matched "*italic*" → correct italic only — regression: bug #219',
        () {
      // Variant: '** and *ok*' — unmatched '**' at start, then a valid '*ok*'.
      const source = '** and *ok*';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.italic);
      // '*ok*' starts at offset 7, ends at offset 11
      expect(els[0].start, 7);
      expect(els[0].end, 11);
    });
  });

  // ---------------------------------------------------------------------------
  // Strikethrough (~~text~~)
  // ---------------------------------------------------------------------------

  group('MdParser.parse — strikethrough', () {
    test('"~~text~~" → [strikethrough(0, 8)]', () {
      final els = MdParser.parse('~~text~~');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.strikethrough);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
    });

    test('"hello ~~world~~ there" → [strikethrough(6, 15)]', () {
      final els = MdParser.parse('hello ~~world~~ there');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.strikethrough);
      expect(els[0].start, 6);
      expect(els[0].end, 15); // '~~world~~' = 9 chars starting at 6 → end 15
    });

    test('unmatched "~~" with no closing → no element', () {
      expect(MdParser.parse('~~no close'), isEmpty);
    });

    test('unmatched "~~" alone → no element', () {
      expect(MdParser.parse('~~'), isEmpty);
    });

    test(
        'unmatched "~~" (no close on line) does not produce italic via fallthrough',
        () {
      // '~~word': no closing '~~' on the line.
      // Both tilde chars must be skipped — neither should become an italic '*' analog.
      // Result: no elements (tildes are plain text).
      expect(MdParser.parse('~~word'), isEmpty);
    });

    test(
        '"~~ ~~ok~~" → greedy: first "~~" closes on nearest "~~", producing one strikethrough',
        () {
      // source = '~~ ~~ok~~' (9 chars, indices 0..8).
      // i=0: sees '~~', closeStart=2; nearest '~~' in [2..9) is at pos 3.
      // → strikethrough(0, 5), content = ' ' (space at pos 2).
      // i=5: 'o','k' plain; then '~~' at pos 7 has no close in [9..9) → skip.
      // Result: one strikethrough(0, 5).
      const source = '~~ ~~ok~~';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.strikethrough);
      expect(els[0].start, 0);
      expect(els[0].end, 5);
    });

    test('"text ~~a~~ ~~b~~" → two separate strikethrough elements', () {
      const source = 'text ~~a~~ ~~b~~';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.strikethrough);
      expect(els[0].start, 5);
      expect(els[0].end, 10); // '~~a~~' = 5 chars at pos 5
      expect(els[1].kind, MdElKind.strikethrough);
      expect(els[1].start, 11);
      expect(els[1].end, 16); // '~~b~~' = 5 chars at pos 11
    });

    test('strikethrough openDelimLen = 2, closeDelimLen = 2', () {
      final el = MdParser.parse('~~hi~~').first;
      expect(el.openDelimLen, 2);
      expect(el.closeDelimLen, 2);
    });

    test('strikethrough isDelimiter: first two and last two chars are delims',
        () {
      // '~~hi~~' → start=0, end=6
      final el = MdParser.parse('~~hi~~').first;
      expect(el.isDelimiter(0), isTrue);
      expect(el.isDelimiter(1), isTrue);
      expect(el.isDelimiter(2), isFalse); // 'h'
      expect(el.isDelimiter(3), isFalse); // 'i'
      expect(el.isDelimiter(4), isTrue);
      expect(el.isDelimiter(5), isTrue);
    });

    test('strikethrough adjacent to bold on same line', () {
      // '**bold** ~~struck~~'
      const source = '**bold** ~~struck~~';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.bold);
      expect(els[0].start, 0);
      expect(els[0].end, 8);
      expect(els[1].kind, MdElKind.strikethrough);
      expect(els[1].start, 9);
      expect(els[1].end, 19);
    });

    test('strikethrough adjacent to italic on same line', () {
      // '*italic* ~~struck~~'
      const source = '*italic* ~~struck~~';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.italic);
      expect(els[1].kind, MdElKind.strikethrough);
    });

    test('"~~~~" (empty strikethrough content) → no element', () {
      expect(MdParser.parse('~~~~'), isEmpty);
    });

    test('cross-line strikethrough → no element', () {
      expect(
        MdParser.parse('~~crosses\nlines~~')
            .where((e) => e.kind == MdElKind.strikethrough),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Inline code (`code`)
  // ---------------------------------------------------------------------------

  group('MdParser.parse — inline code', () {
    test('"` code`" → [inlineCode(0, 6)]', () {
      final els = MdParser.parse('`code`');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els[0].start, 0);
      expect(els[0].end, 6);
    });

    test('"hello `world` there" → [inlineCode(6, 13)]', () {
      final els = MdParser.parse('hello `world` there');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els[0].start, 6);
      expect(els[0].end, 13);
    });

    test('unmatched backtick → no element', () {
      expect(MdParser.parse('`no close'), isEmpty);
    });

    test('inline code content with bold delimiters → not parsed as bold', () {
      // Content '**x**' inside backticks must not produce bold elements.
      final els = MdParser.parse('`**x**`');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      // No nested bold element.
      expect(els.where((e) => e.kind == MdElKind.bold), isEmpty);
    });

    test('inline code content with italic delimiters → not parsed as italic',
        () {
      final els = MdParser.parse('`_text_`');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
    });

    test('inline code content with "~~" → not parsed as strikethrough', () {
      final els = MdParser.parse('`~~text~~`');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els.where((e) => e.kind == MdElKind.strikethrough), isEmpty);
    });

    test('inline code content with "[" → not parsed as link', () {
      final els = MdParser.parse('`[not a link](url)`');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els.where((e) => e.kind == MdElKind.link), isEmpty);
    });

    test('inlineCode openDelimLen = 1, closeDelimLen = 1', () {
      final el = MdParser.parse('`hi`').first;
      expect(el.openDelimLen, 1);
      expect(el.closeDelimLen, 1);
    });

    test('inlineCode isDelimiter: first and last char', () {
      // '`hi`' → start=0, end=4
      final el = MdParser.parse('`hi`').first;
      expect(el.isDelimiter(0), isTrue);
      expect(el.isDelimiter(1), isFalse); // 'h'
      expect(el.isDelimiter(2), isFalse); // 'i'
      expect(el.isDelimiter(3), isTrue);
    });

    test('inline code adjacent to bold: "`code` **bold**"', () {
      const source = '`code` **bold**';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els[1].kind, MdElKind.bold);
    });

    test('inline code takes priority: backtick inside code span closes span',
        () {
      // Ensure the parser stops at the first closing backtick.
      // '`a b`c' → one inlineCode(0, 5), then 'c' is plain.
      final els = MdParser.parse('`a b`c');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.inlineCode);
      expect(els[0].start, 0);
      expect(els[0].end, 5);
    });

    test('cross-line inline code → no element', () {
      expect(
        MdParser.parse('`crosses\nlines`')
            .where((e) => e.kind == MdElKind.inlineCode),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // h4–h6
  // ---------------------------------------------------------------------------

  group('MdParser.parse — h4, h5, h6', () {
    test('"#### Hello" → [h4(0, 10)]', () {
      final els = MdParser.parse('#### Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h4);
      expect(els[0].start, 0);
      expect(els[0].end, 10);
    });

    test('"##### Hello" → [h5(0, 11)]', () {
      final els = MdParser.parse('##### Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h5);
      expect(els[0].start, 0);
      expect(els[0].end, 11);
    });

    test('"###### Hello" → [h6(0, 12)]', () {
      final els = MdParser.parse('###### Hello');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h6);
      expect(els[0].start, 0);
      expect(els[0].end, 12);
    });

    test('h4 openDelimLen = 5 ("#### ")', () {
      final el = MdParser.parse('#### Hi').first;
      expect(el.kind, MdElKind.h4);
      expect(el.openDelimLen, 5);
    });

    test('h5 openDelimLen = 6 ("##### ")', () {
      final el = MdParser.parse('##### Hi').first;
      expect(el.kind, MdElKind.h5);
      expect(el.openDelimLen, 6);
    });

    test('h6 openDelimLen = 7 ("###### ")', () {
      final el = MdParser.parse('###### Hi').first;
      expect(el.kind, MdElKind.h6);
      expect(el.openDelimLen, 7);
    });

    test('"####### not a heading" → no element (7 hashes)', () {
      // GFM only defines h1–h6.
      expect(MdParser.parse('####### too deep'), isEmpty);
    });

    test('h4–h6 isDelimiter: prefix chars are delimiters, content is not', () {
      final el = MdParser.parse('#### Title').first;
      // '#### ' = 5 chars (indices 0–4) are delimiters.
      for (var i = 0; i < 5; i++) {
        expect(el.isDelimiter(i), isTrue, reason: 'index $i should be delim');
      }
      expect(el.isDelimiter(5), isFalse); // 'T'
    });

    test('existing h1–h3 still parse correctly after h4–h6 added', () {
      final h1 = MdParser.parse('# H1').first;
      expect(h1.kind, MdElKind.h1);
      final h2 = MdParser.parse('## H2').first;
      expect(h2.kind, MdElKind.h2);
      final h3 = MdParser.parse('### H3').first;
      expect(h3.kind, MdElKind.h3);
    });

    test('h4 on one line, bold on next → two elements', () {
      const source = '#### Title\n**bold**';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.h4);
      expect(els[1].kind, MdElKind.bold);
    });
  });

  // ---------------------------------------------------------------------------
  // Bare URL autolinks
  // ---------------------------------------------------------------------------

  group('MdParser.parse — bare URL autolinks', () {
    test('"https://example.com" → [autolink(0, 19)]', () {
      const url = 'https://example.com';
      final els = MdParser.parse(url);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].start, 0);
      expect(els[0].end, url.length);
    });

    test('"http://example.com" → [autolink(0, 18)]', () {
      const url = 'http://example.com';
      final els = MdParser.parse(url);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].start, 0);
      expect(els[0].end, url.length);
    });

    test('bare URL mid-line: "visit https://example.com now"', () {
      const source = 'visit https://example.com now';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].start, 6); // 'visit ' = 6
      expect(els[0].end, 6 + 'https://example.com'.length);
    });

    test('URL at end of line (no trailing whitespace)', () {
      const source = 'see https://example.com';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].end, source.length);
    });

    test('URL ends at first whitespace', () {
      // 'https://a.com more' → URL is only 'https://a.com' (13 chars).
      const source = 'https://a.com more text';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].end, 'https://a.com'.length);
    });

    test('bare URL preceded by non-space text (no space before url)', () {
      // 'texthttps://example.com' — should still detect the URL.
      // Per spec: URL starts at first char of 'https://'.
      const source = 'texthttps://example.com';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].start, 4); // 'text' = 4 chars
    });

    test('bare URL url field contains the raw URL text', () {
      const url = 'https://example.com';
      final el = MdParser.parse(url).first;
      expect(el.url, url);
    });

    test('URL inside "[text](url)" link is NOT also an autolink', () {
      // The scanner must not double-match a URL already inside a link.
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      // One link element, no autolink.
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.link);
      expect(els.where((e) => e.kind == MdElKind.autolink), isEmpty);
    });

    test('URL inside "![alt](url)" image is NOT an autolink', () {
      // Block image line — no autolink inside the parentheses.
      final els = MdParser.parse('![alt](https://example.com/img.jpg)');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
      expect(els.where((e) => e.kind == MdElKind.autolink), isEmpty);
    });

    test('no ftp:// autolink (only https:// and http:// supported)', () {
      expect(
        MdParser.parse('ftp://example.com')
            .where((e) => e.kind == MdElKind.autolink),
        isEmpty,
      );
    });

    test('no bare domain detection (must start with scheme)', () {
      expect(
        MdParser.parse('example.com').where((e) => e.kind == MdElKind.autolink),
        isEmpty,
      );
    });

    test('autolink openDelimLen = 0 (URL is content, no delimiter to hide)',
        () {
      final el = MdParser.parse('https://a.com').first;
      expect(el.openDelimLen, 0);
    });

    test('autolink closeDelimLen = 0', () {
      final el = MdParser.parse('https://a.com').first;
      expect(el.closeDelimLen, 0);
    });

    test('autolink isDelimiter: no chars are delimiters', () {
      final el = MdParser.parse('https://a.com').first;
      for (var i = el.start; i < el.end; i++) {
        expect(el.isDelimiter(i), isFalse);
      }
    });

    test('autolink url field contains the extracted URL', () {
      const url = 'https://example.com/path?q=1';
      final el = MdParser.parse(url).first;
      expect(el.url, url);
    });

    test('two bare URLs on one line → two autolink elements', () {
      const source = 'https://a.com and https://b.com';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.autolink);
      expect(els[0].url, 'https://a.com');
      expect(els[1].kind, MdElKind.autolink);
      expect(els[1].url, 'https://b.com');
    });

    // Word-boundary guard tests (regression for mid-word URL match).
    test(
        '"texthttps://example.com" → no autolink (no whitespace before scheme)',
        () {
      // The 'h' of 'https://' is immediately preceded by 't' (a letter),
      // so the word-boundary guard must suppress the match.
      expect(
        MdParser.parse('texthttps://example.com')
            .where((e) => e.kind == MdElKind.autolink),
        isEmpty,
      );
    });

    test(
        '"word https://example.com" (space before) → one autolink — word-boundary guard',
        () {
      const source = 'word https://example.com';
      final els =
          MdParser.parse(source).where((e) => e.kind == MdElKind.autolink);
      expect(els, hasLength(1));
      expect(els.first.url, 'https://example.com');
    });

    test(
        '"(https://example.com)" — "(" precedes URL → no autolink (non-whitespace boundary)',
        () {
      // Decision: only whitespace (space, tab) or start-of-line counts as a
      // valid word boundary before a URL. Any other character — including
      // punctuation like '(' — suppresses the match.  This keeps the rule
      // simple and avoids false positives in pasted code or prose.
      expect(
        MdParser.parse('(https://example.com)')
            .where((e) => e.kind == MdElKind.autolink),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Blockquotes ('> ')
  // ---------------------------------------------------------------------------

  group('MdParser.parse — blockquote', () {
    test('">> text" → one blockquote element, start/end, openDelimLen = 2', () {
      const source = '> text';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
      expect(els[0].start, 0);
      expect(els[0].end, source.length);
      expect(els[0].openDelimLen, 2);
    });

    test('blockquote openDelimLen = 2 ("> " prefix)', () {
      final el = MdParser.parse('> hello').first;
      expect(el.openDelimLen, 2);
    });

    test('blockquote closeDelimLen = 0', () {
      final el = MdParser.parse('> hello').first;
      expect(el.closeDelimLen, 0);
    });

    test('blockquote isDelimiter: first two chars are delimiters', () {
      // '> text' → '>' at 0 and ' ' at 1 are delimiters; 't' at 2 is content.
      final el = MdParser.parse('> text').first;
      expect(el.isDelimiter(0), isTrue);
      expect(el.isDelimiter(1), isTrue);
      expect(el.isDelimiter(2), isFalse);
    });

    test('">text" (no space after ">") → NOT a blockquote (plain text)', () {
      expect(
        MdParser.parse('>text').where((e) => e.kind == MdElKind.blockquote),
        isEmpty,
      );
    });

    test('">" alone (no space) → NOT a blockquote', () {
      expect(
        MdParser.parse('>').where((e) => e.kind == MdElKind.blockquote),
        isEmpty,
      );
    });

    test('">" followed by space alone → blockquote with empty content', () {
      // "> " (greater-than + space, nothing after) — we emit the element
      // because the prefix is valid.  Content length = 0 (nothing after "> ").
      // Decision: emit the element so the cursor-inside reveal model works
      // correctly when the user places the cursor on an otherwise-blank
      // blockquote line.
      final els = MdParser.parse('> ');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
    });

    test('multi-line: one blockquote element per "> " line', () {
      const source = '> line one\n> line two';
      final els = MdParser.parse(source);
      expect(els, hasLength(2));
      expect(els[0].kind, MdElKind.blockquote);
      expect(els[0].start, 0);
      expect(els[0].end, 10); // '> line one' = 10 chars
      expect(els[1].kind, MdElKind.blockquote);
      expect(els[1].start, 11); // after '\n'
      expect(els[1].end, 21); // '> line two' = 10 chars
    });

    test('blockquote followed by plain line → only blockquote element', () {
      const source = '> quoted\nplain text';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
    });

    test('collapsedMarker for blockquote is empty string', () {
      final el = MdParser.parse('> hi').first;
      expect(el.collapsedMarker, '');
    });
  });

  // ---------------------------------------------------------------------------
  // Horizontal rule ('---', '***', '___')
  // ---------------------------------------------------------------------------

  group('MdParser.parse — horizontal rule', () {
    test('"---" → hr element', () {
      final els = MdParser.parse('---');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });

    test('"***" → hr element', () {
      final els = MdParser.parse('***');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });

    test('"___" → hr element', () {
      final els = MdParser.parse('___');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });

    test('"----" (4 dashes) → hr element', () {
      final els = MdParser.parse('----');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });

    test('"--" (only 2 chars) → NOT an hr', () {
      expect(
        MdParser.parse('--').where((e) => e.kind == MdElKind.hr),
        isEmpty,
      );
    });

    test('"---x" → NOT an hr (extra non-dash character)', () {
      expect(
        MdParser.parse('---x').where((e) => e.kind == MdElKind.hr),
        isEmpty,
      );
    });

    test('hr start/end covers full source line', () {
      const source = '---';
      final el = MdParser.parse(source).first;
      expect(el.start, 0);
      expect(el.end, 3);
    });

    test('hr in multi-line source has correct start/end', () {
      const source = 'before\n---\nafter';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
      // 'before\n' = 7 chars → hr starts at 7, ends at 10.
      expect(els[0].start, 7);
      expect(els[0].end, 10);
    });

    test('hr openDelimLen = line length (entire line is delimiter)', () {
      final el = MdParser.parse('---').first;
      expect(el.openDelimLen, 3);
    });

    test('hr closeDelimLen = 0', () {
      final el = MdParser.parse('---').first;
      expect(el.closeDelimLen, 0);
    });

    test('all hr chars are isDelimiter', () {
      final el = MdParser.parse('---').first;
      for (var i = el.start; i < el.end; i++) {
        expect(el.isDelimiter(i), isTrue);
      }
    });

    test('hr collapsedMarker is empty string', () {
      final el = MdParser.parse('---').first;
      expect(el.collapsedMarker, '');
    });

    test('"- - -" (dashes with spaces) → hr element (spaces allowed)', () {
      // GFM allows optional spaces between hr characters.
      final els = MdParser.parse('- - -');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });
  });
}
