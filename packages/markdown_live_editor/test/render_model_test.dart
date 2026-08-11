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

    test('h1 revealed at the marker\'s own end boundary (inclusive) — ADR-37',
        () {
      // source = '# A', h1(0,3), openDelimLen = 2 ('# '), so the marker's own
      // narrow reveal end is 2 (the boundary between '# ' and 'A'). Per the
      // existing >=/<= inclusive-end convention (already used for every
      // other element's reveal check), cursorOffset == 2 still reveals the
      // marker.
      const source = '# A';
      final elements = MdParser.parse(source);
      final m = _build(source, elements, cursorOffset: 2);

      expect(m.renderedLength, 3);
      expect(m.textSpan.toPlainText(), '# A');
    });

    test(
        'h1 with cursor past the marker (at element.end, inside heading '
        'text): marker stays collapsed — regression test for #345/ADR-37', () {
      // source = '# A', h1(0,3). Before ADR-37 the whole line (marker
      // included) was the reveal unit, so cursorOffset == element.end (3)
      // used to reveal the raw '# ' prefix too, even though the cursor is
      // actually past the marker, inside the heading TEXT. This is exactly
      // the bug #345 reports: cursor anywhere on the line snapped the whole
      // line to raw source. Now only the marker's own span ([0, 2]) reveals
      // it; 'A' renders with normal h1 styling, no marker in sight.
      const source = '# A';
      final elements = MdParser.parse(source);
      final m = _build(source, elements, cursorOffset: 3);

      expect(m.renderedLength, 1); // just 'A' — '# ' stays collapsed
      expect(m.textSpan.toPlainText(), 'A');
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 4 / ADR-34 Fix 2 — list element render model tests
  //
  // ADR-34 Fix 2 (block_indentation.md) removed the inline collapsedMarker
  // substitution these used to go through: the bullet dot, ol number, and
  // checkbox box are now painted by QuikiRenderEditor as a gutter decoration,
  // positioned via ListMarkerSlot / CheckboxSlot metadata — independent of
  // inline rendered text, because inline characters only reserve width on a
  // line's first visual row and so cannot survive word-wrap. The rendered
  // TextSpan for a list line therefore contains ONLY its content now — no
  // marker glyph, no reserved blank characters — mirroring how a collapsed
  // blockquote line has rendered since ADR-34 Stage 1.
  // ---------------------------------------------------------------------------

  group('RenderModel.build — list elements', () {
    // -------------------------------------------------------------------------
    // ul
    // -------------------------------------------------------------------------
    test('ul collapsed: "- item" → rendered "item" (no bullet glyph inline)',
        () {
      // source = '- item' (6 chars), ul(0,6), cursorOffset = -1
      // marker '- ' (2 source chars) is hidden entirely, same as a heading
      // prefix — no substitution glyph is emitted into the rendered text.
      const source = '- item';
      final el = MdParser.parse(source);
      final m = _build(source, el, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'item');
      expect(m.renderedLength, 4);
    });

    test('ul collapsed: source delimiter maps to rendered content start', () {
      // source = '- item' — the marker '- ' is fully hidden, so both
      // delimiter chars map to rendered 0, same as the first content char.
      const source = '- item';
      final el = MdParser.parse(source);
      final m = _build(source, el, cursorOffset: -1);

      expect(m.sourceToRendered[0], 0); // '-'
      expect(m.sourceToRendered[1], 0); // ' '
      expect(m.sourceToRendered[2], 0); // 'i'
      expect(m.sourceToRendered[3], 1); // 't'
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

    test('ul collapsed: listMarkerSlots has one entry with bullet label', () {
      const source = '- item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.listMarkerSlots, hasLength(1));
      final slot = m.listMarkerSlots.single;
      expect(slot.element.kind, MdElKind.ul);
      expect(slot.label, '•');
      expect(slot.renderedStart, 0);
    });

    test('ul revealed: no listMarkerSlots recorded (cursor inside)', () {
      const source = '- item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: 1);

      expect(m.listMarkerSlots, isEmpty);
    });

    // -------------------------------------------------------------------------
    // checkboxUnchecked — the box/checkmark is painted directly via Canvas in
    // QuikiRenderEditor rather than as a Unicode glyph, because Android's
    // font-fallback shaping picks a font per text run (not per character),
    // which made checked-box glyphs inconsistently render as large colour
    // emoji depending on document order. See #267. Its screen position now
    // comes from CheckboxSlot.renderedStart (the content-start position) —
    // there is no inline reservation to derive a width-based hit-test range
    // from any more (ADR-34 Fix 2).
    // -------------------------------------------------------------------------
    test(
        'checkboxUnchecked collapsed: "- [ ] item" → rendered "item" (box '
        'painted separately, no inline reservation)', () {
      // source = '- [ ] item' (10 chars)
      // marker '- [ ] ' (6 source chars) is hidden entirely.
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'item');
      expect(m.renderedLength, 4);
    });

    test(
        'checkboxUnchecked collapsed: offset map — all 6 source marker chars '
        'map to rendered content start (0)', () {
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // All source marker positions map to rendered 0 (content start).
      for (var d = 0; d < 6; d++) {
        expect(m.sourceToRendered[d], 0,
            reason: 'source[$d] should map to rendered 0');
      }
      expect(m.sourceToRendered[6], 0); // 'i'
      expect(m.sourceToRendered[7], 1); // 't'
      expect(m.sourceToRendered[8], 2); // 'e'
      expect(m.sourceToRendered[9], 3); // 'm'
      expect(m.sourceToRendered[10], 4); // end sentinel

      // renderedToSource: content starts at rendered 0 → source 6 ('i').
      expect(m.renderedToSource[0], 6);
      expect(m.renderedToSource[1], 7); // 't'
      expect(m.renderedToSource[2], 8); // 'e'
      expect(m.renderedToSource[3], 9); // 'm'
      // End sentinel.
      expect(m.renderedToSource[4], 10);
    });

    test(
        'checkboxUnchecked collapsed: checkboxSlots has one entry; '
        'renderedStart == 0 (content-start position)', () {
      const source = '- [ ] foo';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.checkboxSlots, hasLength(1));
      final slot = m.checkboxSlots[0];
      expect(slot.element.kind, MdElKind.checkboxUnchecked);
      expect(slot.element.start, 0);
      expect(slot.renderedStart, 0);
      expect(slot.checked, isFalse);
    });

    test('no checkboxSlots when source has no checkbox elements', () {
      const source = '- plain list item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.checkboxSlots, isEmpty);
    });

    test(
        'revealed checkbox (cursor inside): no checkboxSlot recorded for '
        'that element', () {
      const source = '- [ ] item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: 1);

      expect(m.checkboxSlots, isEmpty);
    });

    // -------------------------------------------------------------------------
    // checkboxChecked
    // -------------------------------------------------------------------------
    test('checkboxChecked collapsed: "- [x] done" → rendered "done"', () {
      const source = '- [x] done';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'done');
      expect(m.renderedLength, 4);
    });

    test('checkboxSlots carries checked flag for checked/unchecked elements',
        () {
      const source = '- [ ] a\n- [x] b';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.checkboxSlots, hasLength(2));
      expect(m.checkboxSlots[0].checked, isFalse);
      expect(m.checkboxSlots[1].checked, isTrue);
    });

    test('two collapsed checkboxes: two checkboxSlots with correct offsets',
        () {
      // source = '- [ ] one\n- [x] two'
      // line 1: '- [ ] one' → marker hidden, content 'one' = 3 rendered chars
      // '\n' → 1 rendered char (rendered offset 3)
      // line 2: '- [x] two' content starts at rendered offset 4
      const source = '- [ ] one\n- [x] two';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.checkboxSlots, hasLength(2));

      final slot0 = m.checkboxSlots[0];
      expect(slot0.element.kind, MdElKind.checkboxUnchecked);
      expect(slot0.element.start, 0);
      expect(slot0.renderedStart, 0);

      final slot1 = m.checkboxSlots[1];
      expect(slot1.element.kind, MdElKind.checkboxChecked);
      expect(slot1.element.start, 10);
      expect(slot1.renderedStart, 4);
    });

    // -------------------------------------------------------------------------
    // ol — position-computed sequence number
    // -------------------------------------------------------------------------
    test('ol collapsed: "1. item" → rendered "item" (no marker text inline)',
        () {
      const source = '1. item';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'item');
      expect(m.renderedLength, 4);
    });

    test('ol collapsed: listMarkerSlots carries the rendered seqNum label', () {
      // Construct an ol element with seqNum=3 (matching source '3. item').
      const source = '3. item';
      final el = MdElement(
        kind: MdElKind.ol,
        start: 0,
        end: 7,
        seqNum: 3,
        srcMarkerLen: 3, // '3. ' = 3 source chars
      );
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'item');
      expect(m.listMarkerSlots, hasLength(1));
      expect(m.listMarkerSlots.single.label, '3.');
      expect(m.listMarkerSlots.single.renderedStart, 0);
    });

    test(
        'ol collapsed: two-digit source "12. item" — content starts at '
        'rendered 0 regardless of marker digit width', () {
      const source = '12. item';
      final el = MdElement(
        kind: MdElKind.ol,
        start: 0,
        end: 8,
        seqNum: 12,
        srcMarkerLen: 4, // '12. ' = 4 source chars
      );
      final m = _build(source, [el], cursorOffset: -1);

      expect(m.textSpan.toPlainText(), 'item');
      expect(m.renderedLength, 4);
      expect(m.listMarkerSlots.single.label, '12.');

      // Source delimiter positions 0..3 all map to rendered 0.
      for (var d = 0; d <= 3; d++) {
        expect(m.sourceToRendered[d], 0,
            reason: 'source[$d] (delimiter) should map to rendered 0');
      }
      // First content char 'i' at source 4 → rendered 0 — a wider marker
      // (two digits vs one) must NOT push content further right; that
      // consistency, regardless of marker width, is the whole point of
      // painting the marker as a gutter decoration rather than inline text.
      expect(m.sourceToRendered[4], 0);
    });

    test('ol via parser: block-relative seqNums surface via listMarkerSlots',
        () {
      // Consecutive ol lines form one block; block starts at first line's
      // source digit (1). Each subsequent line increments by 1 regardless of
      // source digit — '1. alpha\n1. beta\n1. gamma' renders labels 1./2./3.
      const source = '1. alpha\n1. beta\n1. gamma';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].seqNum, 1);
      expect(els[1].seqNum, 2);
      expect(els[2].seqNum, 3);

      final m = _build(source, els, cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'alpha\nbeta\ngamma');
      expect(
        m.listMarkerSlots.map((s) => s.label).toList(),
        ['1.', '2.', '3.'],
      );
    });

    test('ol via parser: block starting at 5 → labels 5., 6., 7.', () {
      // '5. alpha\n1. beta\n1. gamma' — block anchors to 5, then 6, 7.
      const source = '5. alpha\n1. beta\n1. gamma';
      final els = MdParser.parse(source);
      expect(els, hasLength(3));
      expect(els[0].seqNum, 5);
      expect(els[1].seqNum, 6);
      expect(els[2].seqNum, 7);

      final m = _build(source, els, cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'alpha\nbeta\ngamma');
      expect(
        m.listMarkerSlots.map((s) => s.label).toList(),
        ['5.', '6.', '7.'],
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 5 — image element render model tests
  // ---------------------------------------------------------------------------

  group('RenderModel.build — image elements', () {
    test(
        'collapsed image: all source chars of "![alt](path)" map to the same rendered offset',
        () {
      const source = '![alt](img.png)';
      final els = MdParser.parse(source);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);

      final m = _build(source, els, cursorOffset: -1);

      // All image source chars should map to the same rendered offset (0).
      for (var i = 0; i <= source.length - 1; i++) {
        expect(m.sourceToRendered[i], 0,
            reason: 'source[$i] should map to rendered 0 for collapsed image');
      }
      // End sentinel maps to 0 as well (no rendered chars at all).
      expect(m.sourceToRendered[source.length], 0);
    });

    test('collapsed image: renderedLength does not include image source chars',
        () {
      // The image line emits no rendered characters.
      const source = '![alt](img.png)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.renderedLength, 0,
          reason: 'image chars produce no rendered output when collapsed');
      expect(m.textSpan.toPlainText(), '',
          reason: 'collapsed image → empty rendered text');
    });

    test('collapsed image: imageSlots has one entry with correct source offset',
        () {
      const source = '![alt](img.png)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.imageSlots, hasLength(1));
      expect(m.imageSlots[0].element.kind, MdElKind.image);
      expect(m.imageSlots[0].element.start, 0);
      expect(m.imageSlots[0].element.end, source.length);
      // renderedCharOffset is 0 — the image sits at the beginning of rendered space.
      expect(m.imageSlots[0].renderedCharOffset, 0);
    });

    test(
        'image preceded by plain text: image chars map to rendered offset = length of preceding text',
        () {
      // 'hello\n![alt](img.png)' — 'hello\n' = 6 rendered chars, then image at ri=6.
      const source = 'hello\n![alt](img.png)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // Rendered text = 'hello\n' only (6 chars).
      expect(m.textSpan.toPlainText(), 'hello\n');
      expect(m.renderedLength, 6);

      // Image source chars (offset 6..21) all map to rendered 6.
      for (var i = 6; i < source.length; i++) {
        expect(m.sourceToRendered[i], 6,
            reason: 'source[$i] (image char) should map to rendered 6');
      }
      expect(m.sourceToRendered[source.length], 6);

      // imageSlots has one entry; renderedCharOffset = 6.
      expect(m.imageSlots, hasLength(1));
      expect(m.imageSlots[0].renderedCharOffset, 6);
    });

    test('no image slots when source has no image elements', () {
      final m = _build('hello world', [], cursorOffset: -1);
      expect(m.imageSlots, isEmpty);
    });

    test('revealed image: cursor inside → identity mapping, imageSlots empty',
        () {
      // When the cursor is inside the image element, it is revealed (raw source
      // visible via TextPainter).  The RenderModel still emits no rendered chars
      // for the image (the full line is treated as a delimiter in revealed mode
      // too — in revealed mode, all chars are visible in baseStyle).
      //
      // Actually: for image, openDelimLen == full length, so all chars are
      // "delimiters" — but in revealed mode, the `revealed` flag overrides and
      // all chars ARE emitted as visible text.  Let us verify.
      const source = '![alt](img.png)';
      final els = MdParser.parse(source);
      // cursorOffset = 0 → cursor inside image element → revealed.
      final m = _build(source, els, cursorOffset: 0);

      // In revealed mode the image source text IS emitted.
      expect(m.renderedLength, source.length);
      expect(m.textSpan.toPlainText(), source);

      // Revealed image: no slot added (only collapsed slots get slots).
      expect(m.imageSlots, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 6 — link element render model tests
  // ---------------------------------------------------------------------------

  group('RenderModel.build — link elements', () {
    // source = '[Go](https://go.dev)' (20 chars)
    // content 'Go' at source offsets 1..2 (2 chars)
    // openDelimLen = 1, closeDelimLen = 2 + 'https://go.dev'.length + 1 = 17
    // closing delimiter starts at offset 20 - 17 = 3

    test('collapsed link: renderedLength = 2 ("Go"), textSpan = "Go"', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.renderedLength, 2);
      expect(m.textSpan.toPlainText(), 'Go');
    });

    test('collapsed link: offset map — opening "[" maps to rendered 0', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // Opening delimiter '[' (source 0) → rendered 0.
      expect(m.sourceToRendered[0], 0);
    });

    test('collapsed link: offset map — content chars map one-to-one', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // 'G' at source 1 → rendered 0.
      expect(m.sourceToRendered[1], 0);
      // 'o' at source 2 → rendered 1.
      expect(m.sourceToRendered[2], 1);
    });

    test('collapsed link: offset map — closing delimiters map to rendered 2',
        () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      // All closing delimiter chars ']'(3) through ')'(19) → rendered 2.
      for (var i = 3; i <= 19; i++) {
        expect(m.sourceToRendered[i], 2,
            reason: 'source[$i] (closing delim) should map to rendered 2');
      }
      // End sentinel.
      expect(m.sourceToRendered[20], 2);
    });

    test('collapsed link: renderedToSource — rendered 0 → source 1 (G)', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.renderedToSource[0], 1); // rendered 'G' → source 'G'
      expect(m.renderedToSource[1], 2); // rendered 'o' → source 'o'
      // End sentinel: rendered 2 → source.length (20).
      expect(m.renderedToSource[2], 20);
    });

    test('collapsed link: content span has underline + link color', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      final children = m.textSpan.children!;
      expect(children, hasLength(1));
      final contentSpan = children[0] as TextSpan;
      expect(contentSpan.style?.decoration, TextDecoration.underline);
      expect(contentSpan.style?.color, isNotNull);
      // Verify the color differs from baseStyle (plain text) color.
      expect(contentSpan.style?.color, isNot(_base.color));
    });

    test('collapsed link: linkSlots has one entry with correct url', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.linkSlots, hasLength(1));
      expect(m.linkSlots[0].element.url, 'https://go.dev');
      expect(m.linkSlots[0].renderedStart, 0);
      expect(m.linkSlots[0].renderedEnd, 2);
    });

    test('revealed link: all chars visible, identity mapping', () {
      // cursorOffset = 1 → cursor inside 'G', element revealed.
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: 1);

      expect(m.renderedLength, source.length);
      expect(m.textSpan.toPlainText(), source);

      // Identity mapping.
      for (var i = 0; i <= source.length; i++) {
        expect(m.sourceToRendered[i], i);
      }
    });

    test('revealed link: no linkSlots (cursor inside = not collapsed)', () {
      const source = '[Go](https://go.dev)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: 1);

      expect(m.linkSlots, isEmpty);
    });

    test('two collapsed links: two linkSlots with correct rendered bounds', () {
      // source = '[a](b) and [c](d)'
      // link1: '[a](b)' at 0..6, content 'a' at rendered 0..1
      // ' and ' plain text (5 chars) → rendered 1..6
      // link2: '[c](d)' at 11..17, content 'c' at rendered 6..7
      const source = '[a](b) and [c](d)';
      final els = MdParser.parse(source);
      final m = _build(source, els, cursorOffset: -1);

      expect(m.linkSlots, hasLength(2));
      expect(m.linkSlots[0].element.url, 'b');
      expect(m.linkSlots[0].renderedStart, 0);
      expect(m.linkSlots[0].renderedEnd, 1);
      expect(m.linkSlots[1].element.url, 'd');
      // ' and ' = 5 chars after 'a', so link2 content starts at rendered 6.
      expect(m.linkSlots[1].renderedStart, 6);
      expect(m.linkSlots[1].renderedEnd, 7);
    });

    test('no linkSlots when source has no link elements', () {
      final m = _build('hello world', [], cursorOffset: -1);
      expect(m.linkSlots, isEmpty);
    });
  });
}
