import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

// ---------------------------------------------------------------------------
// Nested / combined inline markdown — ADR-33, Stage 1 (paragraphs & headings).
//
// The parser implements CommonMark's delimiter-run + flanking-rule algorithm
// for the QuKi-Notes inline subset (emphasis, strong, strikethrough, inline
// code, links, autolinks, backslash escapes). Test inputs are drawn from the
// CommonMark 0.30 spec and github/cmark-gfm's GFM extension tests; each case
// notes the source input and the rendering it must match on GitHub.
// ---------------------------------------------------------------------------

/// Returns the elements of [kind] from parsing [src], in document order.
List<MdElement> _ofKind(String src, MdElKind kind) =>
    MdParser.parse(src).where((e) => e.kind == kind).toList();

MdElement? _first(String src, MdElKind kind) {
  final m = _ofKind(src, kind);
  return m.isEmpty ? null : m.first;
}

const _base = TextStyle(fontSize: 16.0, color: Color(0xFFFFFFFF));

RenderModel _build(String source, {int cursorOffset = -1}) {
  return RenderModel.build(
    source: source,
    elements: MdParser.parse(source),
    cursorOffset: cursorOffset,
    baseStyle: _base,
  );
}

/// Flattens the rendered TextSpan into a list of (text, style) leaves.
List<TextSpan> _leaves(RenderModel m) {
  final out = <TextSpan>[];
  void walk(TextSpan s) {
    if (s.children == null) {
      if ((s.text ?? '').isNotEmpty) out.add(s);
      return;
    }
    for (final c in s.children!) {
      walk(c as TextSpan);
    }
  }

  walk(m.textSpan);
  return out;
}

/// Style of the rendered character at rendered offset [ri].
TextStyle? _styleAtRendered(RenderModel m, int ri) {
  var acc = 0;
  for (final leaf in _leaves(m)) {
    final len = leaf.text!.length;
    if (ri < acc + len) return leaf.style;
    acc += len;
  }
  return null;
}

void main() {
  // -------------------------------------------------------------------------
  // Emphasis / strong resolution (CommonMark) — single level, unchanged output
  // -------------------------------------------------------------------------
  group('emphasis resolution — flanking basics', () {
    test('"*foo bar*" → one em over the whole run (CommonMark ex. 360-style)',
        () {
      final el = _first('*foo bar*', MdElKind.italic);
      expect(el, isNotNull);
      expect(el!.start, 0);
      expect(el.end, 9);
    });

    test('"a * foo bar*" → no emphasis (opener followed by space cannot open)',
        () {
      // CommonMark: "* " is not left-flanking, so it is not an opener.
      expect(_ofKind('a * foo bar*', MdElKind.italic), isEmpty);
    });

    test('"**foo bar**" → one strong run', () {
      final el = _first('**foo bar**', MdElKind.bold);
      expect(el, isNotNull);
      expect(el!.start, 0);
      expect(el.end, 11);
    });
  });

  // -------------------------------------------------------------------------
  // Intraword emphasis: `*` allowed inside a word, `_` disallowed. This is the
  // load-bearing distinction that a naive stack cannot express (ADR-33).
  // -------------------------------------------------------------------------
  group('intraword emphasis (* vs _)', () {
    test('"foo*bar*baz" → italic on "bar" (intraword * allowed)', () {
      // GitHub: foo<em>bar</em>baz
      final el = _first('foo*bar*baz', MdElKind.italic);
      expect(el, isNotNull);
      expect(el!.start, 3);
      expect(el.end, 8);
    });

    test('"foo_bar_baz" → NO emphasis (intraword _ disallowed)', () {
      // GitHub: foo_bar_baz (literal underscores)
      expect(_ofKind('foo_bar_baz', MdElKind.italic), isEmpty);
    });

    test('"_foo bar_" → italic (underscore at word boundaries)', () {
      final el = _first('_foo bar_', MdElKind.italic);
      expect(el, isNotNull);
      expect(el!.start, 0);
      expect(el.end, 9);
    });

    test('"5_6_78" → NO emphasis (underscore between alphanumerics)', () {
      expect(_ofKind('5_6_78', MdElKind.italic), isEmpty);
    });

    test(
        '"foo__bar__baz" → NO strong (intraword _ disallowed at any run length)',
        () {
      // CommonMark applies the intraword underscore restriction to runs of any
      // length, so `__` between word chars cannot open/close. GitHub renders
      // foo__bar__baz literally. (By contrast `**`/`*` are allowed intraword —
      // see "foo**bar**baz".)
      expect(_ofKind('foo__bar__baz', MdElKind.bold), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Nested and combined formatting — the core of ADR-33.
  // -------------------------------------------------------------------------
  group('nested / combined emphasis', () {
    test('"**bold *italic* text**" → strong[0,22] containing em[7,15]', () {
      final els = MdParser.parse('**bold *italic* text**');
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(bold.start, 0);
      expect(bold.end, 22);
      expect(italic.start, 7);
      expect(italic.end, 15);
      // Nesting: italic is strictly inside bold.
      expect(bold.start < italic.start && italic.end < bold.end, isTrue);
    });

    test('"**foo *bar* baz**" → strong containing em (CommonMark ex. ~396)',
        () {
      final els = MdParser.parse('**foo *bar* baz**');
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(bold.start, 0);
      expect(bold.end, 17);
      expect(italic.start, 6);
      expect(italic.end, 11);
    });

    test('"*foo **bar** baz*" → em containing strong (CommonMark ex. ~400)',
        () {
      final els = MdParser.parse('*foo **bar** baz*');
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      expect(italic.start, 0);
      expect(italic.end, 17);
      expect(bold.start, 5);
      expect(bold.end, 12);
    });

    test('"~~**_text_**~~" → strike ⊃ strong ⊃ em (triple nest)', () {
      final els = MdParser.parse('~~**_text_**~~');
      final strike = els.firstWhere((e) => e.kind == MdElKind.strikethrough);
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(strike.start, 0);
      expect(strike.end, 14);
      expect(bold.start, 2);
      expect(bold.end, 12);
      expect(italic.start, 4);
      expect(italic.end, 10);
      // Strictly nested.
      expect(strike.start < bold.start && bold.end < strike.end, isTrue);
      expect(bold.start < italic.start && italic.end < bold.end, isTrue);
    });

    test('"***x***" → strong containing em (rule-of-three split)', () {
      final els = MdParser.parse('***x***');
      expect(els.where((e) => e.kind == MdElKind.bold), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), hasLength(1));
    });

    test('"foo**bar**baz" → intraword strong (CommonMark ex. ~410)', () {
      final el = _first('foo**bar**baz', MdElKind.bold);
      expect(el, isNotNull);
      expect(el!.start, 3);
      expect(el.end, 10);
    });
  });

  // -------------------------------------------------------------------------
  // Code-span precedence: code binds before emphasis, and its interior is
  // fully literal.
  // -------------------------------------------------------------------------
  group('code-span precedence', () {
    test('"`*a*`" → inline code only, no emphasis inside', () {
      final els = MdParser.parse('`*a*`');
      expect(els.where((e) => e.kind == MdElKind.inlineCode), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
    });

    test('"*a `code` b*" → emphasis spans across a code span', () {
      // Emphasis around a code span resolves; the backticks inside are literal.
      final els = MdParser.parse('*a `code` b*');
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      final code = els.firstWhere((e) => e.kind == MdElKind.inlineCode);
      expect(italic.start, 0);
      expect(italic.end, 12);
      expect(code.start, 3);
      expect(code.end, 9);
      expect(italic.start < code.start && code.end < italic.end, isTrue);
    });

    test('"`` `code with ** inside` `` " → asterisks in code are literal', () {
      final els = MdParser.parse('`code with ** inside`');
      expect(els.where((e) => e.kind == MdElKind.inlineCode), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.bold), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Backslash escapes (CommonMark) — ADR-33 in-scope.
  // -------------------------------------------------------------------------
  group('backslash escapes', () {
    test('"\\*not italic\\*" → two escape elements, no italic', () {
      const src = '\\*not italic\\*';
      final els = MdParser.parse(src);
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
      final escapes = els.where((e) => e.kind == MdElKind.escape).toList();
      expect(escapes, hasLength(2));
      // First escape hides the leading backslash at 0, shows '*' at 1.
      expect(escapes[0].start, 0);
      expect(escapes[0].end, 2);
      expect(escapes[0].openDelimLen, 1);
      expect(escapes[0].isDelimiter(0), isTrue); // backslash hidden
      expect(escapes[0].isDelimiter(1), isFalse); // '*' shown literally
    });

    test('"\\[not a link\\]" → escapes, no link', () {
      const src = '\\[not a link\\]';
      final els = MdParser.parse(src);
      expect(els.where((e) => e.kind == MdElKind.link), isEmpty);
      expect(els.where((e) => e.kind == MdElKind.escape), hasLength(2));
    });

    test('escape for every in-scope ASCII punctuation delimiter char', () {
      // Each of these characters is markdown-significant inline; a preceding
      // backslash must neutralize it.
      for (final ch in ['*', '_', '~', '`', '[', ']', '(', ')', '!', r'\\']) {
        final src = '\\$ch';
        final els = MdParser.parse(src);
        expect(els.where((e) => e.kind == MdElKind.escape), hasLength(1),
            reason: 'backslash before "$ch" should produce one escape element');
      }
    });

    test('"\\A" → NO element (backslash before a letter stays literal)', () {
      // CommonMark: a backslash before a non-punctuation char is a literal
      // backslash; nothing is dropped and no escape is formed.
      expect(MdParser.parse('\\A'), isEmpty);
    });

    test('trailing lone backslash → no element', () {
      expect(MdParser.parse('end\\'), isEmpty);
    });

    test('escaped delimiter does not open emphasis: "\\*a*" → no italic', () {
      // The first '*' is escaped, so the run "*a*" has no opener → no emphasis.
      final els = MdParser.parse('\\*a*');
      expect(els.where((e) => e.kind == MdElKind.italic), isEmpty);
      expect(els.where((e) => e.kind == MdElKind.escape), hasLength(1));
    });

    test('escape is inline-only: "\\# foo" is a paragraph, not a heading', () {
      // Block-prefix detection sees the leading backslash and does not treat
      // the line as a heading; the escape then hides the backslash inline.
      final els = MdParser.parse('\\# foo');
      expect(els.where((e) => e.kind == MdElKind.h1), isEmpty);
      expect(els.where((e) => e.kind == MdElKind.escape), hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // GFM strikethrough (github/cmark-gfm strikethrough extension).
  // -------------------------------------------------------------------------
  group('GFM strikethrough', () {
    test('"~~Hi~~ Hello" → strikethrough on "Hi"', () {
      final el = _first('~~Hi~~ Hello', MdElKind.strikethrough);
      expect(el, isNotNull);
      expect(el!.start, 0);
      expect(el.end, 6);
    });

    test('single "~" is not strikethrough', () {
      expect(_ofKind('~notdeleted~', MdElKind.strikethrough), isEmpty);
    });

    test('strikethrough combined with strong: "~~**bold**~~"', () {
      final els = MdParser.parse('~~**bold**~~');
      final strike = els.firstWhere((e) => e.kind == MdElKind.strikethrough);
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      expect(strike.start, 0);
      expect(strike.end, 12);
      expect(bold.start, 2);
      expect(bold.end, 10);
    });
  });

  // -------------------------------------------------------------------------
  // Links / autolinks combine with emphasis, both around AND inside link text.
  // -------------------------------------------------------------------------
  group('links combined with emphasis', () {
    test('"**[GitHub](https://github.com)**" → strong containing link', () {
      final els = MdParser.parse('**[GitHub](https://github.com)**');
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final link = els.firstWhere((e) => e.kind == MdElKind.link);
      expect(bold.start, 0);
      expect(bold.end, 32);
      expect(link.url, 'https://github.com');
      expect(bold.start < link.start && link.end < bold.end, isTrue);
    });

    test('autolink inside strong: "**see https://a.com now**"', () {
      final els = MdParser.parse('**see https://a.com now**');
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final auto = els.firstWhere((e) => e.kind == MdElKind.autolink);
      expect(bold.start, 0);
      expect(auto.url, 'https://a.com');
      expect(bold.start < auto.start && auto.end < bold.end, isTrue);
    });

    // ADR-33: link *text* is recursively scanned for nested emphasis.
    test('"[**bold link**](url)" → link containing a bold label', () {
      final els = MdParser.parse('[**bold link**](url)');
      final link = els.firstWhere((e) => e.kind == MdElKind.link);
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      expect(link.start, 0);
      expect(link.url, 'url');
      // '[' then '**' → bold begins at offset 1; label 'bold link' is 9 chars.
      expect(bold.start, 1);
      expect(bold.end, 14); // '**bold link**' = 13 chars starting at 1
      expect(link.start < bold.start && bold.end < link.end, isTrue);
    });

    test('"[a *b* ~~c~~](url)" → link containing italic and strikethrough', () {
      final els = MdParser.parse('[a *b* ~~c~~](url)');
      expect(els.where((e) => e.kind == MdElKind.link), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.strikethrough), hasLength(1));
    });

    test('"[`code`](url)" → link containing an inline code label', () {
      final els = MdParser.parse('[`code`](url)');
      expect(els.where((e) => e.kind == MdElKind.link), hasLength(1));
      final code = els.firstWhere((e) => e.kind == MdElKind.inlineCode);
      expect(code.start, 1);
      expect(code.end, 7);
    });

    test('autolink is suppressed inside link text: "[go https://x.com](u)"',
        () {
      // The recursive link-text scan runs with links (and autolinks) disabled,
      // so a bare URL in the label is NOT turned into a nested link — a link
      // cannot contain another link (CommonMark). Only the outer link results.
      final els = MdParser.parse('[go https://x.com](u)');
      expect(els.where((e) => e.kind == MdElKind.link), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.autolink), isEmpty);
      expect(els.firstWhere((e) => e.kind == MdElKind.link).url, 'u');
    });
  });

  // -------------------------------------------------------------------------
  // RenderModel — nested emphasis inside link text renders combined styles and
  // reports correct LinkSlot bounds (delimiters inside the label are hidden).
  // -------------------------------------------------------------------------
  group('RenderModel — nested emphasis in link text', () {
    test(
        '"[**b**](url)" collapsed: label "b" is bold + underlined + link color',
        () {
      final m = _build('[**b**](url)', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'b');
      final style = _styleAtRendered(m, 0); // 'b'
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.decoration, TextDecoration.underline);
      // Link color differs from the base (white) text color.
      expect(style?.color, isNot(_base.color));
    });

    test('"[**b**](url)" collapsed: LinkSlot bounds reflect the 1-char label',
        () {
      // Source label "**b**" is 5 chars but renders as 1 ('b'); renderedEnd must
      // be renderedStart + 1, not renderedStart + 5.
      final m = _build('[**b**](url)', cursorOffset: -1);
      expect(m.linkSlots, hasLength(1));
      expect(m.linkSlots[0].renderedStart, 0);
      expect(m.linkSlots[0].renderedEnd, 1);
      expect(m.linkSlots[0].element.url, 'url');
    });

    test('"[a **b** c](url)" collapsed: label renders "a b c", slot spans it',
        () {
      final m = _build('[a **b** c](url)', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'a b c');
      expect(m.linkSlots, hasLength(1));
      expect(m.linkSlots[0].renderedStart, 0);
      expect(m.linkSlots[0].renderedEnd, 5); // 'a b c'
      // The 'b' (rendered index 2) is bold + link-underlined; 'a' (index 0) is
      // link-underlined but not bold.
      expect(_styleAtRendered(m, 2)?.fontWeight, FontWeight.bold);
      expect(_styleAtRendered(m, 2)?.decoration, TextDecoration.underline);
      expect(_styleAtRendered(m, 0)?.fontWeight, isNot(FontWeight.bold));
      expect(_styleAtRendered(m, 0)?.decoration, TextDecoration.underline);
    });

    test('cursor inside "[**b**](url)" reveals the whole link raw', () {
      final m = _build('[**b**](url)', cursorOffset: 3); // inside 'b'
      expect(m.textSpan.toPlainText(), '[**b**](url)');
      expect(m.linkSlots, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Inline scanning inside headings — previously impossible (ADR-33 Stage 1).
  // -------------------------------------------------------------------------
  group('inline formatting in headings', () {
    test('"# **bold** heading" → h1 + bold at content offset', () {
      final els = MdParser.parse('# **bold** heading');
      expect(els.where((e) => e.kind == MdElKind.h1), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      // '# ' prefix is 2 chars → bold begins at offset 2.
      expect(bold.start, 2);
      expect(bold.end, 10);
    });

    test('"### nested **bold *italic***" → h3 with nested emphasis', () {
      final els = MdParser.parse('### nested **bold *italic***');
      expect(els.where((e) => e.kind == MdElKind.h3), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.bold), hasLength(1));
      expect(els.where((e) => e.kind == MdElKind.italic), hasLength(1));
    });

    test('"## `code` in a heading" → h2 + inline code', () {
      final els = MdParser.parse('## `code` in a heading');
      expect(els.where((e) => e.kind == MdElKind.h2), hasLength(1));
      final code = els.firstWhere((e) => e.kind == MdElKind.inlineCode);
      expect(code.start, 3); // '## ' = 3 chars
    });

    test('heading inline scan starts after the correct prefix for h1..h6', () {
      for (final entry in {
        '# ': MdElKind.h1,
        '## ': MdElKind.h2,
        '### ': MdElKind.h3,
        '#### ': MdElKind.h4,
        '##### ': MdElKind.h5,
        '###### ': MdElKind.h6,
      }.entries) {
        final prefix = entry.key;
        final src = '$prefix**b**';
        final els = MdParser.parse(src);
        final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
        expect(bold.start, prefix.length,
            reason: 'bold should start right after "$prefix"');
      }
    });
  });

  // -------------------------------------------------------------------------
  // RenderModel — combined styles at a character, and delimiter hiding.
  // -------------------------------------------------------------------------
  group('RenderModel — combined nested styles', () {
    test('"**bold *italic* text**" collapsed: all delimiters hidden', () {
      final m = _build('**bold *italic* text**', cursorOffset: -1);
      // Rendered text drops every ** and * delimiter.
      expect(m.textSpan.toPlainText(), 'bold italic text');
    });

    test('nested char carries BOTH bold weight and italic style', () {
      // 'a **b *c* d** e' collapsed → 'a b c d e'; the 'c' (rendered index 4)
      // is inside both bold and italic.
      final m = _build('a **b *c* d** e', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'a b c d e');
      final style = _styleAtRendered(m, 4); // 'c'
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.fontStyle, FontStyle.italic);
      // A bold-only char ('b' at rendered index 2) is bold but not italic.
      final bStyle = _styleAtRendered(m, 2);
      expect(bStyle?.fontWeight, FontWeight.bold);
      expect(bStyle?.fontStyle, isNot(FontStyle.italic));
    });

    test('"~~**x**~~" collapsed: strike + bold combine (line-through + bold)',
        () {
      final m = _build('~~**x**~~', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'x');
      final style = _styleAtRendered(m, 0); // 'x'
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.decoration, TextDecoration.lineThrough);
    });

    test('single-level bold still renders exactly as before (no regression)',
        () {
      final m = _build('**bold**', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'bold');
      final style = _styleAtRendered(m, 0);
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.fontStyle, isNot(FontStyle.italic));
    });

    test('bold heading with inline bold: content is heading-sized', () {
      final m = _build('# **big**', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'big');
      final style = _styleAtRendered(m, 0);
      // h1 content is 2x base font (32) and bold.
      expect(style?.fontSize, 32.0);
      expect(style?.fontWeight, FontWeight.bold);
    });
  });

  // -------------------------------------------------------------------------
  // Whole-chain reveal: cursor anywhere inside a nested run reveals the entire
  // OUTERMOST element as raw source (ADR-33 "Reveal-on-cursor semantics").
  // -------------------------------------------------------------------------
  group('RenderModel — whole-chain reveal', () {
    const src = 'a **b *c* d** e';

    test('cursor inside the inner italic reveals the WHOLE outer strong', () {
      // Cursor at offset 7 (the inner 'c'): the entire '**b *c* d**' span shows
      // as raw source, not just the '*c*' piece.
      final m = _build(src, cursorOffset: 7);
      expect(m.textSpan.toPlainText(), src);
    });

    test('cursor inside the outer-but-not-inner region also reveals the whole',
        () {
      // Cursor at offset 4 (the 'b', inside bold but not italic).
      final m = _build(src, cursorOffset: 4);
      expect(m.textSpan.toPlainText(), src);
    });

    test('cursor at the outermost end boundary still reveals the whole', () {
      // bold covers [2,13); cursor at 13 (== end) still reveals per ADR-31.
      final m = _build(src, cursorOffset: 13);
      expect(m.textSpan.toPlainText(), src);
    });

    test('cursor entirely outside collapses everything (delimiters hidden)',
        () {
      final m = _build(src, cursorOffset: 0);
      expect(m.textSpan.toPlainText(), 'a b c d e');
    });

    test('cursor in a sibling run does not reveal an unrelated run', () {
      // Two independent runs; cursor in the first must not reveal the second.
      const s = '*one* and **two**';
      final m = _build(s, cursorOffset: 2); // inside '*one*'
      // '*one*' revealed as raw, '**two**' still collapsed to 'two'.
      expect(m.textSpan.toPlainText(), '*one* and two');
    });
  });
}
