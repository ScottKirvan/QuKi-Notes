import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

const _base = TextStyle(fontSize: 16.0, color: Color(0xFFFFFFFF));

RenderModel _build(
  String source,
  List<MdElement> elements, {
  int cursorOffset = -1,
}) {
  return RenderModel.build(
    source: source,
    elements: elements,
    cursorOffset: cursorOffset,
    baseStyle: _base,
  );
}

void main() {
  group('RenderModel.build', () {
    test('empty source → renderedLength 0, both arrays length 1 containing 0',
        () {
      final m = _build('', []);
      expect(m.renderedLength, 0);
      expect(m.sourceToRendered, hasLength(1));
      expect(m.sourceToRendered[0], 0);
      expect(m.renderedToSource, hasLength(1));
      expect(m.renderedToSource[0], 0);
    });

    test(
        'plain text no elements → identity mapping, textSpan plain text == source',
        () {
      const source = 'hello';
      final m = _build(source, [], cursorOffset: -1);
      expect(m.renderedLength, 5);
      expect(m.sourceToRendered, [0, 1, 2, 3, 4, 5]);
      expect(m.renderedToSource, [0, 1, 2, 3, 4, 5]);
      expect(m.textSpan.toPlainText(), 'hello');
    });

    test(
        'bold collapsed: delimiters absent from rendered text, content in bold style',
        () {
      // source = '**bold**', bold(0,8), cursorOffset = -1
      const source = '**bold**';
      final el = MdElement(kind: MdElKind.bold, start: 0, end: 8);
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.renderedLength, 4); // 'bold'
      expect(m.textSpan.toPlainText(), 'bold');

      // Opening ** both map to rendered 0.
      expect(m.sourceToRendered[0], 0);
      expect(m.sourceToRendered[1], 0);
      // 'b' at source 2 maps to rendered 0.
      expect(m.sourceToRendered[2], 0);
      // 'o' at source 3 maps to rendered 1.
      expect(m.sourceToRendered[3], 1);
      // Closing ** map to rendered 4.
      expect(m.sourceToRendered[6], 4);
      expect(m.sourceToRendered[7], 4);
      // End sentinel.
      expect(m.sourceToRendered[8], 4);

      // Rendered 'b' (index 0) → source index 2.
      expect(m.renderedToSource[0], 2);
      // End sentinel.
      expect(m.renderedToSource[4], 8);

      // Content span uses bold style.
      final children = m.textSpan.children!;
      expect(children, hasLength(1));
      final contentSpan = children[0] as TextSpan;
      expect(contentSpan.style?.fontWeight, FontWeight.bold);
    });

    test(
        'bold revealed: cursor inside → identity mapping, all chars use baseStyle color',
        () {
      // source = '**bold**', bold(0,8), cursorOffset = 3
      const source = '**bold**';
      final el = MdElement(kind: MdElKind.bold, start: 0, end: 8);
      final m = _build(source, [el], cursorOffset: 3);

      expect(m.renderedLength, 8); // all chars visible
      expect(m.textSpan.toPlainText(), '**bold**');

      // sourceToRendered is identity [0..8].
      for (var i = 0; i <= 8; i++) {
        expect(m.sourceToRendered[i], i);
      }

      // All chars use baseStyle — delimiters and content merge into a single span.
    });

    test('heading h1 collapsed: prefix absent, content in 2x font + bold', () {
      // source = '# Hello', h1(0,7), cursorOffset = -1
      const source = '# Hello';
      final el = MdElement(kind: MdElKind.h1, start: 0, end: 7);
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.renderedLength, 5); // 'Hello'
      expect(m.textSpan.toPlainText(), 'Hello');

      // '#' and ' ' (source 0,1) both map to rendered 0.
      expect(m.sourceToRendered[0], 0);
      expect(m.sourceToRendered[1], 0);
      // 'H' at source 2 maps to rendered 0.
      expect(m.sourceToRendered[2], 0);

      // Rendered 'H' (index 0) → source index 2.
      expect(m.renderedToSource[0], 2);

      // Content span: fontSize 32, bold.
      final children = m.textSpan.children!;
      expect(children, hasLength(1));
      final contentSpan = children[0] as TextSpan;
      expect(contentSpan.style?.fontSize, 32.0);
      expect(contentSpan.style?.fontWeight, FontWeight.bold);
    });

    test('italic collapsed: delimiters absent, content in italic style', () {
      // source = '*hi*', italic(0,4), cursorOffset = -1
      const source = '*hi*';
      final el = MdElement(kind: MdElKind.italic, start: 0, end: 4);
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.renderedLength, 2); // 'hi'
      expect(m.textSpan.toPlainText(), 'hi');

      final children = m.textSpan.children!;
      expect(children, hasLength(1));
      final contentSpan = children[0] as TextSpan;
      expect(contentSpan.style?.fontStyle, FontStyle.italic);
    });

    test('text before + bold collapsed + text after', () {
      // source = 'a **b** c', bold(2,7), cursorOffset = 0
      // rendered = 'a b c' (5 chars)
      const source = 'a **b** c';
      final el = MdElement(kind: MdElKind.bold, start: 2, end: 7);
      final m = _build(source, [el], cursorOffset: 0);

      expect(m.renderedLength, 5);

      // Opening ** → rendered 2.
      expect(m.sourceToRendered[2], 2);
      expect(m.sourceToRendered[3], 2);
      // 'b' at source 4 → rendered 2.
      expect(m.sourceToRendered[4], 2);
      // Closing ** → rendered 3.
      expect(m.sourceToRendered[5], 3);
      expect(m.sourceToRendered[6], 3);
      // Space after ** at source 7 → rendered 3.
      expect(m.sourceToRendered[7], 3);

      // renderedForSource(4) == 2 (the bold 'b')
      expect(m.renderedForSource(4), 2);
      // sourceForRendered(2) == 4 (the bold 'b')
      expect(m.sourceForRendered(2), 4);
    });

    test('newline passes through: heading + newline + plain text', () {
      // source = '# H\nplain', h1(0,3), cursorOffset = -1
      // rendered = 'H\nplain'
      const source = '# H\nplain';
      final el = MdElement(kind: MdElKind.h1, start: 0, end: 3);
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'H\nplain');
    });

    test(
        'heading revealed: cursor inside prefix → all chars visible including # prefix',
        () {
      // source = '# Hello', h1(0,7), cursorOffset = 0
      const source = '# Hello';
      final el = MdElement(kind: MdElKind.h1, start: 0, end: 7);
      final m = _build(source, [el], cursorOffset: 0);

      expect(m.renderedLength, 7);
      expect(m.textSpan.toPlainText(), '# Hello');

      // All chars use baseStyle — delimiters and content merge into a single span.
    });

    test('bold revealed at element.end: all chars visible', () {
      // source = '**x**', bold(0,5), cursorOffset = 5 (= element.end)
      // With cursorOffset <= element.end, the element is still revealed.
      const source = '**x**';
      final el = MdElement(kind: MdElKind.bold, start: 0, end: 5);
      final m = _build(source, [el], cursorOffset: 5);

      expect(m.renderedLength, 5);
      expect(m.textSpan.toPlainText(), '**x**');
    });

    test('h1 revealed at element.end: delimiter chars visible', () {
      // source = '# A', h1(0,3), cursorOffset = 3 (= source.length = element.end)
      // With cursorOffset <= element.end, the element is still revealed.
      const source = '# A';
      final elements = MdParser.parse(source);
      final m = _build(source, elements, cursorOffset: 3);

      expect(m.renderedLength, 3);
      expect(m.textSpan.toPlainText(), '# A');
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 4 — list element render model tests
  // ---------------------------------------------------------------------------

  group('RenderModel.build — list elements', () {
    // -------------------------------------------------------------------------
    // ul
    // -------------------------------------------------------------------------
    test('ul collapsed: "- item" → rendered "• item"', () {
      // source = '- item' (6 chars), ul(0,6), cursorOffset = -1
      // marker '- ' (2 source chars) → '• ' (2 rendered chars)
      // content 'item' (4 chars) → 'item' (4 chars)
      // rendered total = '• item' (6 chars)
      const source = '- item';
      final el = MdParser.parse(source);
      final m = _build(source, el, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), '• item');
      expect(m.renderedLength, 6);
    });

    test('ul collapsed: source delimiter maps to rendered marker start', () {
      // source = '- item', marker '• ' starts at rendered 0.
      // srcToRnd[0] = 0 (first '-' maps to rendered 0)
      // srcToRnd[1] = 0 (space maps to rendered 0)
      // srcToRnd[2] = 2 (first content char 'i' maps to rendered 2)
      const source = '- item';
      final el = MdParser.parse(source);
      final m = _build(source, el, cursorOffset: -1);

      expect(m.sourceToRendered[0], 0); // '-'
      expect(m.sourceToRendered[1], 0); // ' '
      expect(m.sourceToRendered[2], 2); // 'i'
      expect(m.sourceToRendered[3], 3); // 't'
    });

    test('ul revealed: source shown as-is', () {
      // cursor inside element → all source chars visible
      const source = '- item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: 1);

      expect(m.textSpan.toPlainText(), '- item');
      expect(m.renderedLength, 6);

      // Identity mapping.
      for (var i = 0; i <= 6; i++) {
        expect(m.sourceToRendered[i], i);
      }
    });

    // -------------------------------------------------------------------------
    // checkboxUnchecked — variable-length substitution (6 src → 2 rendered)
    // -------------------------------------------------------------------------
    test('checkboxUnchecked collapsed: "- [ ] item" → rendered "☐ item"', () {
      // source = '- [ ] item' (10 chars)
      // marker '- [ ] ' (6 source chars) → '☐ ' (2 rendered chars)
      // content 'item' (4 chars)
      // rendered = '☐ item' (6 chars)
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), '☐ item');
      expect(m.renderedLength, 6);
    });

    test(
        'checkboxUnchecked collapsed: offset map — 6 source marker chars → 2 rendered',
        () {
      // source = '- [ ] item'
      // src offsets 0..5 (the marker '- [ ] ') all map to rendered 0
      // src offset 6 ('i') maps to rendered 2
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // All source marker positions map to rendered 0 (start of '☐ ').
      for (var d = 0; d < 6; d++) {
        expect(m.sourceToRendered[d], 0,
            reason: 'source[$d] should map to rendered 0');
      }
      // Content starts at rendered 2.
      expect(m.sourceToRendered[6], 2); // 'i'
      expect(m.sourceToRendered[7], 3); // 't'
      expect(m.sourceToRendered[8], 4); // 'e'
      expect(m.sourceToRendered[9], 5); // 'm'
      expect(m.sourceToRendered[10], 6); // end sentinel

      // renderedToSource: rendered 0 and 1 (the '☐ ') map to source 0.
      expect(m.renderedToSource[0], 0); // '☐' → source 0
      expect(m.renderedToSource[1], 0); // ' ' → source 0
      // Content chars.
      expect(m.renderedToSource[2], 6); // 'i'
      expect(m.renderedToSource[3], 7); // 't'
      expect(m.renderedToSource[4], 8); // 'e'
      expect(m.renderedToSource[5], 9); // 'm'
      // End sentinel.
      expect(m.renderedToSource[6], 10);
    });

    test(
        'checkboxUnchecked collapsed: tapping rendered marker resolves inside element',
        () {
      // sourceForRendered(0) and sourceForRendered(1) must both be inside the
      // element range [0, 10) — so a tap on the marker triggers reveal.
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      final src0 = m.sourceForRendered(0);
      final src1 = m.sourceForRendered(1);
      expect(els[0].containsOffset(src0), isTrue,
          reason: 'rendered 0 → source $src0 should be inside element');
      expect(els[0].containsOffset(src1), isTrue,
          reason: 'rendered 1 → source $src1 should be inside element');
    });

    // -------------------------------------------------------------------------
    // checkboxChecked
    // -------------------------------------------------------------------------
    test('checkboxChecked collapsed: "- [x] done" → rendered "☑ done"', () {
      const source = '- [x] done';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), '☑ done');
      expect(m.renderedLength, 6);
    });

    // -------------------------------------------------------------------------
    // ol — position-computed sequence number
    // -------------------------------------------------------------------------
    test('ol collapsed: seqNum=1 source "1. item" → rendered "1. item"', () {
      // '1. item': marker '1. ' (3 src) → '1. ' (3 rendered) — same length here
      const source = '1. item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), '1. item');
      expect(m.renderedLength, 7);
    });

    test('ol collapsed with seqNum=3 renders "3. " regardless of source digits',
        () {
      // Construct an ol element manually with seqNum=3 but source text '1. item'.
      // The rendered marker should be '3. '.
      const source = '1. item';
      // Build the element manually so we control seqNum.
      final el = MdElement(
        kind: MdElKind.ol,
        start: 0,
        end: 7,
        seqNum: 3,
        srcOlDelimLen: 3, // '1. ' = 3 source chars
      );
      final m = _build(source, [el], cursorOffset: -1);

      // Marker '3. ' emitted; content 'item' follows.
      expect(m.textSpan.toPlainText(), '3. item');
      expect(m.renderedLength, 7);
    });

    test('ol collapsed: two-digit source "12. item" with seqNum=1 → "1. item"',
        () {
      // source '12. item' — source delimiter '12. ' = 4 chars, but seqNum=1.
      // rendered marker = '1. ' (3 chars). Net: 4 src → 3 rendered for marker.
      const source = '12. item';
      final el = MdElement(
        kind: MdElKind.ol,
        start: 0,
        end: 8,
        seqNum: 1,
        srcOlDelimLen: 4, // '12. ' = 4 source chars
      );
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.textSpan.toPlainText(), '1. item');
      expect(m.renderedLength, 7);

      // Source delimiter positions 0..3 all map to rendered 0.
      for (var d = 0; d <= 3; d++) {
        expect(m.sourceToRendered[d], 0,
            reason: 'source[$d] (delimiter) should map to rendered 0');
      }
      // First content char 'i' at source 4 → rendered 3.
      expect(m.sourceToRendered[4], 3);
    });

    test('ol sequence via parser: 3-line block → seqNums 1, 2, 3', () {
      // Use a single source with all three lines and render the full model.
      // The rendered text should substitute each source '1.' marker with the
      // position-computed seqNum.
      const source = '1. alpha\n1. beta\n1. gamma';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].seqNum, 1);
      expect(els[1].seqNum, 2);
      expect(els[2].seqNum, 3);

      // Render the whole source collapsed (cursorOffset = -1).
      final m = _build(source, els, cursorOffset: -1);

      // All three lines rendered: markers substituted by seqNum, content preserved.
      expect(m.textSpan.toPlainText(), '1. alpha\n2. beta\n3. gamma');
    });
  });
}
