import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// ---------------------------------------------------------------------------
// Single-line HTML detection — ADR-33, Stage 3.
//
// MdParser must recognize HTML tag/comment syntax and exclude it from inline
// markdown scanning, so markdown-special characters that appear inside a tag
// (e.g. the `*gray*` in `<div style="border: 1px solid *gray*">`) are left
// literal rather than misread as emphasis. Detection only — QuKi-Notes does
// not render HTML.
//
// Two behaviours (both single-line only; multi-line HTML blocks are explicitly
// NOT attempted this stage — see notes/dev/nested_inline_markdown.md):
//   1. A line consisting entirely of one or more HTML tags/comments is excluded
//      from inline scanning — passed through raw.
//   2. An HTML tag appearing mid-line is skipped by the inline scanner, exactly
//      as an inline code span is, without a dedicated visual treatment.
//
// The tag-matching heuristic is permissive, not real HTML grammar: `<` or `</`
// followed by an ASCII letter or `!`, ending at the next `>`.
// ---------------------------------------------------------------------------

/// Returns the elements of [kind] from parsing [src], in document order.
List<MdElement> _ofKind(String src, MdElKind kind) =>
    MdParser.parse(src).where((e) => e.kind == kind).toList();

const _base = TextStyle(fontSize: 16.0, color: Color(0xFFFFFFFF));

RenderModel _build(String source, {int cursorOffset = -1}) {
  return RenderModel.build(
    source: source,
    elements: MdParser.parse(source),
    cursorOffset: cursorOffset,
    baseStyle: _base,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Part 1 — a line that is entirely HTML: no inline scanning, shown raw.
  // -------------------------------------------------------------------------
  group('HTML-only line — no markdown interpreted inside', () {
    test('"<div style=\\"border: 1px solid *gray*\\">" → no emphasis', () {
      const src = '<div style="border: 1px solid *gray*">';
      final els = MdParser.parse(src);
      // The `*gray*` inside the attribute must NOT become italic.
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
      // Nothing at all is parsed out of a bare HTML line.
      expect(els, isEmpty);
    });

    test('attribute containing *, _, `, [ is all left literal', () {
      const src = '<span data-x="*a* _b_ `c` [d](e)">';
      final els = MdParser.parse(src);
      expect(els, isEmpty);
    });

    test('an HTML comment line is passed through raw', () {
      const src = '<!-- a *b* _c_ `d` [e] note -->';
      final els = MdParser.parse(src);
      expect(els, isEmpty);
    });

    test('a lone closing tag "</span>" is an HTML-only line', () {
      expect(MdParser.parse('</span>'), isEmpty);
    });

    test('a declaration "<!DOCTYPE html>" is an HTML-only line', () {
      expect(MdParser.parse('<!DOCTYPE html>'), isEmpty);
    });

    test('multiple tags on one line (open + close) is HTML-only', () {
      // Two complete tags, nothing between them but the (empty) gap → HTML-only.
      expect(MdParser.parse('<br/><hr/>'), isEmpty);
    });

    test('leading/trailing whitespace around a tag stays HTML-only', () {
      expect(MdParser.parse('  <div class="x">  '), isEmpty);
    });

    test('RenderModel renders an HTML-only line as literal source text', () {
      const src = '<div style="border: 1px solid *gray*">';
      final m = _build(src, cursorOffset: -1);
      // Collapsed rendering is the raw line, unchanged — no delimiters hidden.
      expect(m.textSpan.toPlainText(), src);
    });
  });

  // -------------------------------------------------------------------------
  // Part 2 — a mid-line HTML tag is skipped by the inline scanner, exactly
  // like an inline code span. Its attributes are not misparsed, but real
  // markdown on the same line (outside the tag) still resolves.
  // -------------------------------------------------------------------------
  group('inline HTML tag mid-line — skipped, not misparsed', () {
    test('"text <span style=\\"color:red\\"> more" → no emphasis from the tag',
        () {
      const src = 'text <span style="color:red"> more text';
      final els = MdParser.parse(src);
      expect(els, isEmpty);
    });

    test('mid-line tag with *gray* attribute does not italicize', () {
      const src = 'hello <div style="border: 1px solid *gray*"> world';
      final els = MdParser.parse(src);
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
    });

    test('real emphasis outside the tag still resolves; tag internals do not',
        () {
      // `*real*` is genuine emphasis; the `*fake*` inside the tag attribute is
      // not. Exactly one italic element, and it is the outside one.
      const src = '*real* and <span title="*fake*"> tail';
      final italics = _ofKind(src, MdElKind.italic);
      expect(italics, hasLength(1));
      expect(italics.first.start, 0);
      expect(italics.first.end, 6); // '*real*'
    });

    test('emphasis spans across a skipped inline tag', () {
      // The `<b>` tag is skipped like a code span; the italic run still forms
      // from the `*` on either side of it.
      const src = '*a <b> c*';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
      expect(italic.first.start, 0);
      expect(italic.first.end, src.length);
    });

    test('a mid-line closing tag "</em>" is skipped too', () {
      const src = 'done </em> *yes*';
      final italics = _ofKind(src, MdElKind.italic);
      expect(italics, hasLength(1));
      // '*yes*' begins at index 11.
      expect(italics.first.start, 11);
    });
  });

  // -------------------------------------------------------------------------
  // Over-trigger guard — a `<` that is NOT an HTML tag must not swallow real
  // markdown. The heuristic requires `<`/`</` followed by an ASCII letter or
  // `!` and a same-line `>`; anything else is an ordinary character.
  // -------------------------------------------------------------------------
  group('does not over-trigger on non-tag "<"', () {
    test('"a < b and *italic*" → `<` before a space is not a tag', () {
      const src = 'a < b and *italic*';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
      expect(italic.first.start, 10);
      expect(italic.first.end, 18);
    });

    test('"2 < 3 *yes*" → digit comparison is not a tag', () {
      final italic = _ofKind('2 < 3 *yes*', MdElKind.italic);
      expect(italic, hasLength(1));
    });

    test('"i <3 you *love*" → "<3" (digit after <) is not a tag', () {
      final italic = _ofKind('i <3 you *love*', MdElKind.italic);
      expect(italic, hasLength(1));
    });

    test('"<" with no closing ">" on the line is not a tag', () {
      // `<em` never closes on this line → not treated as HTML; the later
      // emphasis still resolves normally.
      const src = 'x <em and *y*';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
    });

    test('a line with text between tags is NOT HTML-only; its text scans', () {
      // `<span>*a*</span>` has content (`*a*`) between the tags, so the line is
      // not "entirely HTML"; the tags are skipped inline but `*a*` italicizes.
      const src = '<span>*a*</span>';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
      expect(italic.first.start, 6); // after '<span>'
      expect(italic.first.end, 9); // '*a*'
    });
  });

  // -------------------------------------------------------------------------
  // Multi-line non-goal (bounded behaviour, pinned so it can't silently drift).
  // A tag opened on one line without a same-line close does NOT suppress
  // scanning on later lines. Each line is classified independently; there is no
  // multi-line HTML-block state (only single-line detection this stage).
  // -------------------------------------------------------------------------
  group('multi-line HTML is not tracked (single-line detection only)', () {
    test('open tag on line 1 does not suppress emphasis on line 2', () {
      // Line 1 `<div` has no same-line `>` → falls through to normal handling
      // (no markdown specials → nothing). Line 2 `*italic*` parses normally.
      const src = '<div\n*italic*';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
      // '<div\n' is 5 chars → line 2 starts at 5; '*italic*' spans [5, 13).
      expect(italic.first.start, 5);
      expect(italic.first.end, 13);
    });

    test('a comment opened on line 1 does not suppress line 2 emphasis', () {
      // `<!--` never closes on its own line, so it is not an HTML-only line;
      // the following line still gets normal inline scanning.
      const src = '<!--\n*x*\n-->';
      final italic = _ofKind(src, MdElKind.italic);
      expect(italic, hasLength(1));
      // '<!--\n' is 5 chars → '*x*' spans [5, 8).
      expect(italic.first.start, 5);
      expect(italic.first.end, 8);
    });

    test('a complete single-line tag between two paragraphs stays isolated', () {
      // Sanity: the HTML-only middle line is skipped, both paragraphs scan.
      const src = '*a*\n<div class="*x*">\n*b*';
      final italics = _ofKind(src, MdElKind.italic);
      // Only '*a*' (line 1) and '*b*' (line 3) — the tag's '*x*' is inert.
      expect(italics, hasLength(2));
    });
  });

  // -------------------------------------------------------------------------
  // Block-prefix interaction — HTML detection is an inline-scan concern; a
  // heading/list line whose content contains an HTML tag still detects the
  // block prefix, then skips the tag inside the scanned content.
  // -------------------------------------------------------------------------
  group('HTML inside block-prefixed content', () {
    test('"# heading <span x=\\"*y*\\">" → h1, no italic from the tag', () {
      const src = '# heading <span x="*y*">';
      final els = MdParser.parse(src);
      expect(els.where((e) => e.kind == MdElKind.h1), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
    });

    test('"- item <b>bold tag</b> *real*" → ul + one italic (outside tag)', () {
      const src = '- item <b>x</b> *real*';
      final els = MdParser.parse(src);
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), hasLength(1));
    });
  });
}
