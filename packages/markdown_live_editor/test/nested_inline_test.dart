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

/// Prefix a collapsed blockquote's rendered content carries at the
/// RenderModel/TextSpan level. ADR-33 Stage 4 reserved four blank characters
/// here so the quoted content sat visibly indented; ADR-34 removed that
/// reservation — visual indentation now comes entirely from QuikiRenderEditor
/// laying the blockquote's line out as its own narrower, offset layout run
/// (see block_indentation_test.dart), which — unlike the blank-character
/// trick — survives word-wrap. RenderModel's own rendered text for a
/// collapsed blockquote is therefore just its content, with no reserved
/// prefix; this constant stays (now empty) so the expressions below that use
/// it read the same as they did pre-ADR-34.
const _bqIndent = '';

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

  // -------------------------------------------------------------------------
  // Inline scanning inside list items and checkboxes — previously impossible
  // (ADR-33 Stage 2, closes #240). The list-item / checkbox / ordered-list
  // content after the block prefix flows through the same recursive inline
  // engine that headings and paragraphs already use.
  // -------------------------------------------------------------------------
  group('inline formatting in list items', () {
    test('"- **bold**" → ul + bold at content offset', () {
      final els = MdParser.parse('- **bold**');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      // '- ' prefix is 2 chars → bold begins at offset 2.
      expect(bold.start, 2);
      expect(bold.end, 10);
    });

    test('"* *italic*" → ul + italic (star bullet prefix)', () {
      final els = MdParser.parse('* *italic*');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(italic.start, 2);
      expect(italic.end, 10);
    });

    test('"+ ~~struck~~" → ul + strikethrough (plus bullet prefix)', () {
      final els = MdParser.parse('+ ~~struck~~');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final strike = els.firstWhere((e) => e.kind == MdElKind.strikethrough);
      expect(strike.start, 2);
      expect(strike.end, 12);
    });

    test('"- `code` item" → ul + inline code', () {
      final els = MdParser.parse('- `code` item');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final code = els.firstWhere((e) => e.kind == MdElKind.inlineCode);
      expect(code.start, 2); // '- ' = 2 chars
      expect(code.end, 8);
    });

    test('"- [link](https://x.com)" → ul + link', () {
      final els = MdParser.parse('- [link](https://x.com)');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final link = els.firstWhere((e) => e.kind == MdElKind.link);
      expect(link.start, 2);
      expect(link.url, 'https://x.com');
    });

    test('"- **bold *italic* text**" → ul with strong containing em (nested)',
        () {
      // Same nesting as the paragraph case '**bold *italic* text**'
      // (bold[0,22], italic[7,15]), shifted by the 2-char '- ' prefix.
      final els = MdParser.parse('- **bold *italic* text**');
      expect(els.where((e) => e.kind == MdElKind.ul), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(bold.start, 2);
      expect(bold.end, 24);
      expect(italic.start, 9);
      expect(italic.end, 17);
      expect(bold.start < italic.start && italic.end < bold.end, isTrue);
    });

    test('"1. *italic*" → ol + italic at content offset', () {
      final els = MdParser.parse('1. *italic*');
      expect(els.where((e) => e.kind == MdElKind.ol), hasLength(1));
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      // '1. ' prefix is 3 chars → italic begins at offset 3.
      expect(italic.start, 3);
      expect(italic.end, 11);
    });

    test('"12. **bold**" → ol + bold, content after 2-digit marker', () {
      final els = MdParser.parse('12. **bold**');
      expect(els.where((e) => e.kind == MdElKind.ol), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      // '12. ' prefix is 4 chars → bold begins at offset 4.
      expect(bold.start, 4);
      expect(bold.end, 12);
    });

    test('ol block-relative numbering is untouched by inline scanning', () {
      // Adding inline scan must not disturb seqNum tracking (block detection
      // happens before any inline scan).
      const source = '1. **a**\n1. *b*\n1. c';
      final els = MdParser.parse(source);
      final ols = els.where((e) => e.kind == MdElKind.ol).toList();
      expect(ols, hasLength(3));
      expect(ols[0].seqNum, 1);
      expect(ols[1].seqNum, 2);
      expect(ols[2].seqNum, 3);
    });

    test('"- [ ] ~~struck~~" → checkboxUnchecked + strikethrough', () {
      final els = MdParser.parse('- [ ] ~~struck~~');
      expect(
          els.where((e) => e.kind == MdElKind.checkboxUnchecked), hasLength(1));
      final strike = els.firstWhere((e) => e.kind == MdElKind.strikethrough);
      // '- [ ] ' prefix is 6 chars → strikethrough begins at offset 6.
      expect(strike.start, 6);
      expect(strike.end, 16);
    });

    test('"- [x] [a link](url)" → checkboxChecked + link', () {
      final els = MdParser.parse('- [x] [a link](url)');
      expect(
          els.where((e) => e.kind == MdElKind.checkboxChecked), hasLength(1));
      final link = els.firstWhere((e) => e.kind == MdElKind.link);
      // '- [x] ' prefix is 6 chars → link begins at offset 6.
      expect(link.start, 6);
      expect(link.url, 'url');
    });

    test('"- [X] **bold *italic***" → checkboxChecked with nested emphasis',
        () {
      final els = MdParser.parse('- [X] **bold *italic***');
      expect(
          els.where((e) => e.kind == MdElKind.checkboxChecked), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(bold.start, 6); // after '- [X] '
      expect(bold.start < italic.start && italic.end < bold.end, isTrue);
    });

    test('list inline scan starts after the correct prefix per kind', () {
      for (final entry in {
        '- ': MdElKind.ul,
        '* ': MdElKind.ul,
        '+ ': MdElKind.ul,
        '1. ': MdElKind.ol,
        '- [ ] ': MdElKind.checkboxUnchecked,
        '- [x] ': MdElKind.checkboxChecked,
      }.entries) {
        final prefix = entry.key;
        final src = '$prefix**b**';
        final els = MdParser.parse(src);
        expect(els.where((e) => e.kind == entry.value), hasLength(1),
            reason: 'line "$src" should be detected as ${entry.value}');
        final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
        expect(bold.start, prefix.length,
            reason: 'bold should start right after "$prefix"');
      }
    });

    test('plain list content still produces no inline elements (regression)',
        () {
      // The four single-level baselines: prefix + plain text → block only.
      for (final src in ['- item', '1. item', '- [ ] task', '- [x] done']) {
        final els = MdParser.parse(src);
        expect(els, hasLength(1), reason: '"$src" should be one block element');
        expect(els[0].isBlock, isTrue);
      }
    });
  });

  // -------------------------------------------------------------------------
  // RenderModel — list/checkbox content renders through the shared inline path
  // with no list-specific special-casing (ADR-33 Stage 2).
  // -------------------------------------------------------------------------
  group('RenderModel — inline formatting in list items', () {
    // ADR-34 Fix 2 (block_indentation.md) removed the inline collapsedMarker
    // substitution for ul/ol/checkbox — the bullet dot, ol number, and
    // checkbox box are now painted by QuikiRenderEditor as a gutter
    // decoration via ListMarkerSlot/CheckboxSlot, not emitted into the
    // rendered TextSpan. So a list line's rendered text is now content-only,
    // same as it already was for a blockquote line.
    test('"- **bold**" collapsed → "bold", content is bold', () {
      final m = _build('- **bold**', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'bold');
      // No marker consumes rendered width; 'b' is at rendered offset 0.
      expect(_styleAtRendered(m, 0)?.fontWeight, FontWeight.bold);
    });

    test('"1. *italic*" collapsed → "italic", content is italic', () {
      final m = _build('1. *italic*', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'italic');
      // No marker consumes rendered width; 'i' is at rendered offset 0.
      expect(_styleAtRendered(m, 0)?.fontStyle, FontStyle.italic);
    });

    test('"- [ ] **urgent** call" collapsed: checkbox slot + bold content', () {
      final m = _build('- [ ] **urgent** call', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'urgent call');
      // The checkbox glyph slot is still produced (marker unaffected by content).
      expect(m.checkboxSlots, hasLength(1));
      expect(m.checkboxSlots[0].renderedStart, 0);
      expect(m.checkboxSlots[0].checked, isFalse);
      // 'u' of 'urgent' is at rendered offset 0 and must be bold (no marker
      // consumes rendered width any more).
      expect(_styleAtRendered(m, 0)?.fontWeight, FontWeight.bold);
      // ' call' (past the bold run) is not bold.
      expect(_styleAtRendered(m, 7)?.fontWeight, isNot(FontWeight.bold));
    });

    test('nested char in a list item carries BOTH bold and italic', () {
      // '- a **b *c* d** e' collapsed → 'a b c d e' (no bullet glyph
      // inline); the 'c' is inside both bold and italic.
      final m = _build('- a **b *c* d** e', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'a b c d e');
      // 'a ' (2) + 'b ' (2) → 'c' at rendered offset 4.
      final style = _styleAtRendered(m, 4);
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.fontStyle, FontStyle.italic);
    });

    test('"- **bold**" collapsed: listMarkerSlots carries the bullet label',
        () {
      final m = _build('- **bold**', cursorOffset: -1);
      expect(m.listMarkerSlots, hasLength(1));
      expect(m.listMarkerSlots.single.label, '•');
      expect(m.listMarkerSlots.single.renderedStart, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Marker-scoped reveal inside a list item (ADR-37 / #345). Superseded
  // behavior: the block used to be the outermost reveal unit for the whole
  // line, so a cursor anywhere on the line — including deep inside a nested
  // inline run — snapped the ENTIRE line (marker included) to raw source.
  // ADR-37 narrows the '- ' marker's own reveal to just its own source range
  // (openDelimLen); past the marker, content behaves exactly like an
  // unadorned paragraph — the covering inline chain (if any) reveals on its
  // own, and the marker stays collapsed (bullet slot still painted) the
  // whole time, matching the identically-shaped assertions in the top-level
  // 'RenderModel — whole-chain reveal' group above (same content string,
  // same cursor offsets shifted by the 2-char '- ' prefix).
  // -------------------------------------------------------------------------
  group('RenderModel — marker-scoped reveal inside a list item (ADR-37)', () {
    const src = '- a **b *c* d** e';

    test(
        'cursor outside collapses to rendered content (bullet painted '
        'separately — ADR-34 Fix 2)', () {
      final m = _build(src, cursorOffset: -1);
      expect(m.textSpan.toPlainText(), 'a b c d e');
    });

    test(
        'cursor inside the inner italic reveals only the enclosing bold '
        'chain — the "- " marker stays collapsed', () {
      // 'c' is at source offset 9 (after '- a **b *'). Only the covering
      // bold span reveals raw (matching the unprefixed top-level group's
      // identical assertion at cursorOffset 7); the '- ' marker is
      // unaffected — no whole-line snap, and the bullet slot is still
      // painted.
      final m = _build(src, cursorOffset: 9);
      expect(m.textSpan.toPlainText(), 'a **b *c* d** e');
      expect(m.listMarkerSlots, hasLength(1),
          reason: 'marker must stay collapsed — only the inline chain '
              'reveals, not the whole line (regression test for #345)');
    });

    test(
        'cursor inside the bold-but-not-italic region reveals only the '
        'bold chain — the "- " marker stays collapsed', () {
      // 'b' at source offset 6.
      final m = _build(src, cursorOffset: 6);
      expect(m.textSpan.toPlainText(), 'a **b *c* d** e');
      expect(m.listMarkerSlots, hasLength(1));
    });

    test(
        'cursor directly on the marker reveals the raw "- " prefix; content '
        'stays fully collapsed (marker-scoped boundary)', () {
      final m = _build(src, cursorOffset: 1);
      expect(m.textSpan.toPlainText(), '- a b c d e');
      expect(m.listMarkerSlots, isEmpty,
          reason: 'a revealed marker is raw source text, not a slot');
    });

    test(
        'cursor at the marker\'s own end boundary (inclusive) still reveals '
        'the marker', () {
      // markerEnd = block.start + openDelimLen = 0 + 2 = 2, the boundary
      // between '- ' and 'a'. The existing >=/<= inclusive-end convention
      // (already used for every other element's reveal check) applies here
      // too.
      final m = _build(src, cursorOffset: 2);
      expect(m.textSpan.toPlainText(), '- a b c d e');
      expect(m.listMarkerSlots, isEmpty);
    });

    test(
        'cursor one past the marker\'s end boundary no longer reveals the '
        'marker', () {
      final m = _build(src, cursorOffset: 3);
      expect(m.textSpan.toPlainText(), 'a b c d e');
      expect(m.listMarkerSlots, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // Inline scanning inside blockquotes — previously impossible (ADR-33
  // Stage 4). Blockquote content after the '> ' prefix flows through the same
  // recursive inline engine that headings, paragraphs, and list items already
  // use. Blockquotes were wrongly excluded from ADR-33 by carrying forward a
  // stale pre-ADR-31 note; this closes that gap, mirroring Stage 2.
  // -------------------------------------------------------------------------
  group('inline formatting in blockquotes', () {
    test('"> **bold**" → blockquote + bold at content offset', () {
      final els = MdParser.parse('> **bold**');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      // '> ' prefix is 2 chars → bold begins at offset 2.
      expect(bold.start, 2);
      expect(bold.end, 10);
    });

    test('"> *italic*" → blockquote + italic at content offset', () {
      final els = MdParser.parse('> *italic*');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(italic.start, 2);
      expect(italic.end, 10);
    });

    test('"> ~~struck~~" → blockquote + strikethrough', () {
      final els = MdParser.parse('> ~~struck~~');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final strike = els.firstWhere((e) => e.kind == MdElKind.strikethrough);
      expect(strike.start, 2);
      expect(strike.end, 12);
    });

    test('"> `code` here" → blockquote + inline code', () {
      final els = MdParser.parse('> `code` here');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final code = els.firstWhere((e) => e.kind == MdElKind.inlineCode);
      // '> ' = 2 chars.
      expect(code.start, 2);
      expect(code.end, 8);
    });

    test('"> [link](https://x.com)" → blockquote + link', () {
      final els = MdParser.parse('> [link](https://x.com)');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final link = els.firstWhere((e) => e.kind == MdElKind.link);
      expect(link.start, 2);
      expect(link.url, 'https://x.com');
    });

    test('"> visit https://x.com" → blockquote + autolink', () {
      final els = MdParser.parse('> visit https://x.com');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final autolink = els.firstWhere((e) => e.kind == MdElKind.autolink);
      expect(autolink.url, 'https://x.com');
    });

    test(
        '"> **bold *italic* text**" → blockquote with strong containing em '
        '(nested)', () {
      // Same nesting as the paragraph case '**bold *italic* text**'
      // (bold[0,22], italic[7,15]), shifted by the 2-char '> ' prefix.
      final els = MdParser.parse('> **bold *italic* text**');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(bold.start, 2);
      expect(bold.end, 24);
      expect(italic.start, 9);
      expect(italic.end, 17);
      expect(bold.start < italic.start && italic.end < bold.end, isTrue);
    });

    test('empty blockquote "> " → one blockquote element, no inline elements',
        () {
      // '> ' alone: content span [2, 2) is empty, so _scanInline returns [] and
      // no inline elements are produced. The block element is still emitted.
      final els = MdParser.parse('> ');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
    });

    test(
        'plain blockquote content still produces no inline elements '
        '(regression)', () {
      final els = MdParser.parse('> just plain text');
      expect(els, hasLength(1), reason: 'should be one block element only');
      expect(els[0].kind, MdElKind.blockquote);
      expect(els[0].isBlock, isTrue);
    });

    test('blockquote inline scan starts after the 2-char "> " prefix', () {
      final els = MdParser.parse('> **b**');
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      expect(bold.start, 2, reason: 'bold should start right after "> "');
    });
  });

  // -------------------------------------------------------------------------
  // Bare `>` blockquote marker (no space) — CommonMark allows `>` not followed
  // by a space as a blockquote marker (1-char marker), covering both a bare `>`
  // on an otherwise-empty line and `>content` with content immediately after.
  // The marker length is variable (1 or 2), which must flow through
  // openDelimLen / isDelimiter and the inline-scan start offset.
  // -------------------------------------------------------------------------
  group('MdParser.parse — bare ">" blockquote marker', () {
    test('">content" (no space) → blockquote, content inline-scanned', () {
      // Marker is the single '>' (1 char), so content starts at offset 1 and is
      // scanned exactly as '> content' would be after its 2-char marker.
      final els = MdParser.parse('>**bold**');
      final bqs = els.where((e) => e.kind == MdElKind.blockquote).toList();
      expect(bqs, hasLength(1));
      expect(bqs[0].openDelimLen, 1);
      final bold = els.firstWhere((e) => e.kind == MdElKind.bold);
      expect(bold.start, 1, reason: 'bold begins right after the bare ">"');
      expect(bold.end, 9);
    });

    test('">" alone → one blockquote element, empty content, no inline els',
        () {
      final els = MdParser.parse('>');
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
      expect(els[0].openDelimLen, 1);
      expect(els[0].start, 0);
      expect(els[0].end, 1);
    });

    test('">*italic*" (no space) → italic scanned from offset 1', () {
      final els = MdParser.parse('>*italic*');
      expect(els.where((e) => e.kind == MdElKind.blockquote), hasLength(1));
      final italic = els.firstWhere((e) => e.kind == MdElKind.italic);
      expect(italic.start, 1);
      expect(italic.end, 9);
    });

    test('bare ">" and "> " markers coexist across lines', () {
      // Line 0 uses a 2-char '> ' marker; line 1 a 1-char '>' marker.
      const source = '> spaced\n>tight';
      final bqs = MdParser.parse(source)
          .where((e) => e.kind == MdElKind.blockquote)
          .toList();
      expect(bqs, hasLength(2));
      expect(bqs[0].openDelimLen, 2); // '> '
      expect(bqs[1].openDelimLen, 1); // '>'
    });
  });

  // -------------------------------------------------------------------------
  // RenderModel — blockquote content renders through the shared inline path
  // with no blockquote-specific special-casing (ADR-33 Stage 4). Content keeps
  // its muted blockquote color and combines with covering inline styles.
  // -------------------------------------------------------------------------
  group('RenderModel — inline formatting in blockquotes', () {
    // Primer DHC muted — the blockquote content color (mirrors _muted).
    const muted = Color(0xFF9EA7B4);

    test('"> **bold**" collapsed → "bold", content is bold AND muted', () {
      final m = _build('> **bold**', cursorOffset: -1);
      // '> ' and '**' delimiters hidden; the blockquote reserves a blank indent
      // (collapsedMarker) in front, so rendered content is the indent + 'bold'.
      expect(m.textSpan.toPlainText(), '${_bqIndent}bold');
      // First content char sits just past the reserved indent.
      final style = _styleAtRendered(m, _bqIndent.length);
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.color, muted);
    });

    test('"> *italic*" collapsed → "italic", content is italic AND muted', () {
      final m = _build('> *italic*', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), '${_bqIndent}italic');
      final style = _styleAtRendered(m, _bqIndent.length);
      expect(style?.fontStyle, FontStyle.italic);
      expect(style?.color, muted);
    });

    test('nested char in a blockquote carries BOTH bold and italic', () {
      // '> a **b *c* d** e' collapsed → indent + 'a b c d e'; the 'c' is inside
      // both bold and italic (and still muted from the blockquote content style).
      final m = _build('> a **b *c* d** e', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), '${_bqIndent}a b c d e');
      // Content: 'a'(0) ' '(1) 'b'(2) ' '(3) 'c'(4) — shifted right by the
      // reserved indent, so 'c' is at rendered offset indent + 4.
      final style = _styleAtRendered(m, _bqIndent.length + 4);
      expect(style?.fontWeight, FontWeight.bold);
      expect(style?.fontStyle, FontStyle.italic);
      expect(style?.color, muted);
    });

    test('plain "> quote" content is muted (unchanged single-level behavior)',
        () {
      final m = _build('> quote', cursorOffset: -1);
      expect(m.textSpan.toPlainText(), '${_bqIndent}quote');
      // Check the first real content char (past the reserved indent).
      expect(_styleAtRendered(m, _bqIndent.length)?.color, muted);
    });
  });

  // -------------------------------------------------------------------------
  // Blockquote horizontal indentation moved to QuikiRenderEditor (ADR-34):
  // RenderModel's own rendered TextSpan no longer carries any indent-related
  // content (see _bqIndent above), so there is nothing left to assert on
  // dx-within-a-single-unwrapped-TextPainter here — that was the pre-ADR-34
  // mechanism this stage replaced (it never survived word-wrap, which is the
  // bug ADR-34 exists to fix). The equivalent, now wrap-correct, geometry
  // assertions live in block_indentation_test.dart against the real
  // QuikiRenderEditor render object (its public getOffsetForCaret), including
  // the wrapped-line case this file's old version couldn't express at all.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // RenderModel — the left border stripe (BlockquoteSlot) still paints when the
  // blockquote line has inline-formatted content. The stripe is driven by block
  // detection, not content, so a formatted blockquote produces exactly the same
  // single slot at the same rendered start as a plain one (ADR-33 Stage 4).
  // -------------------------------------------------------------------------
  group('RenderModel — blockquote border stripe with formatted content', () {
    test('plain blockquote: one slot, renderedStart 0', () {
      final m = _build('> quote', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(1));
      expect(m.blockquoteSlots[0].renderedStart, 0);
      expect(m.blockquoteSlots[0].element.kind, MdElKind.blockquote);
    });

    test('formatted blockquote: still one slot at renderedStart 0', () {
      // renderedStart is the rendered offset of the (hidden) marker start, which
      // is where the reserved blank indent begins — rendered offset 0 for a
      // top-of-buffer blockquote, exactly as for a plain one. Inline formatting
      // does not disturb the stripe's start.
      final m = _build('> **bold**', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(1));
      expect(m.blockquoteSlots[0].renderedStart, 0);
      expect(m.blockquoteSlots[0].element.kind, MdElKind.blockquote);
    });

    test('two formatted blockquote lines → two stripe slots', () {
      final m = _build('> **a**\n> *b*', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(2));
    });

    test(
        'empty blockquote "> " → still produces a stripe slot (off-by-one fix)',
        () {
      // Regression for bug 2: the empty blockquote content position coincides
      // with where the block is retired from the per-character loop, so the old
      // code never recorded the slot. It must produce exactly one slot now.
      final m = _build('> ', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(1));
      expect(m.blockquoteSlots[0].element.kind, MdElKind.blockquote);
    });

    test('bare ">" alone → empty blockquote produces a stripe slot', () {
      final m = _build('>', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(1));
      expect(m.blockquoteSlots[0].element.kind, MdElKind.blockquote);
    });

    test('empty blockquote slot: spans only the reserved indent (no content)',
        () {
      // An empty blockquote has no content text, but the collapsedMarker still
      // reserves the blank indent, so the rendered span covers exactly that
      // indent — renderedEnd - renderedStart == the indent width. (Before the
      // indent was introduced these two offsets were equal; the reserved indent
      // is what they now differ by.)
      final m = _build('> ', cursorOffset: -1);
      final slot = m.blockquoteSlots.single;
      expect(slot.renderedEnd - slot.renderedStart, _bqIndent.length);
    });

    test('renderedEnd spans the reserved indent plus the rendered content', () {
      // '> hello world' collapses to the reserved indent + 'hello world'; the
      // stripe must be able to cover the whole visual line, so renderedEnd -
      // renderedStart equals indent + content length (this is what lets the
      // paint layer span a wrapped line's full height, not just its first row).
      final m = _build('> hello world', cursorOffset: -1);
      final slot = m.blockquoteSlots.single;
      expect(slot.renderedStart, 0);
      expect(
        slot.renderedEnd - slot.renderedStart,
        _bqIndent.length + 'hello world'.length,
      );
    });

    test('consecutive blockquote slots are adjacent (mergeable into one run)',
        () {
      // The paint layer merges slots whose elements are one '\n' apart into a
      // single continuous stripe; assert that relationship holds here.
      final m = _build('> a\n> b', cursorOffset: -1);
      expect(m.blockquoteSlots, hasLength(2));
      final first = m.blockquoteSlots[0].element;
      final second = m.blockquoteSlots[1].element;
      expect(first.end + 1, second.start);
    });
  });

  // -------------------------------------------------------------------------
  // groupBlockquoteRuns — consecutive blockquote lines merge into one run so
  // QuikiRenderEditor paints a single continuous stripe (bug 3). A gap (a
  // non-blockquote line, or a revealed line with no slot) breaks the run.
  // -------------------------------------------------------------------------
  group('groupBlockquoteRuns', () {
    test('two consecutive "> " lines → one run of two slots', () {
      final m = _build('> a\n> b', cursorOffset: -1);
      final runs = groupBlockquoteRuns(m.blockquoteSlots);
      expect(runs, hasLength(1));
      expect(runs.single, hasLength(2));
    });

    test('three consecutive blockquote lines → one run of three slots', () {
      final m = _build('> a\n> b\n> c', cursorOffset: -1);
      final runs = groupBlockquoteRuns(m.blockquoteSlots);
      expect(runs, hasLength(1));
      expect(runs.single, hasLength(3));
    });

    test('blockquote, plain line, blockquote → two separate runs', () {
      // The middle plain line produces no blockquote slot, so the two
      // blockquote lines are not adjacent and must not merge.
      final m = _build('> a\nplain\n> c', cursorOffset: -1);
      final runs = groupBlockquoteRuns(m.blockquoteSlots);
      expect(runs, hasLength(2));
      expect(runs[0], hasLength(1));
      expect(runs[1], hasLength(1));
    });

    test('empty input → no runs', () {
      expect(groupBlockquoteRuns(const []), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Marker-scoped reveal inside a blockquote (ADR-37 / #345). Superseded
  // behavior: the block used to be the outermost reveal unit for the whole
  // line, so a cursor anywhere on the line — including deep inside a nested
  // inline run — snapped the ENTIRE line (the '> ' marker included) to raw
  // source. ADR-37 narrows the marker's own reveal to just its own source
  // range (openDelimLen); past the marker, content behaves exactly like an
  // unadorned paragraph — the covering inline chain (if any) reveals on its
  // own, and the marker stays collapsed (border stripe still painted) the
  // whole time.
  // -------------------------------------------------------------------------
  group('RenderModel — marker-scoped reveal inside a blockquote (ADR-37)', () {
    const src = '> a **b *c* d** e';

    test('cursor outside collapses to rendered content (no raw markers)', () {
      final m = _build(src, cursorOffset: -1);
      // Collapsed: reserved blockquote indent (now empty, ADR-34) + content.
      expect(m.textSpan.toPlainText(), '${_bqIndent}a b c d e');
    });

    test(
        'cursor inside the inner italic reveals only the enclosing bold '
        'chain — the "> " marker stays collapsed', () {
      // 'c' is at source offset 9 (after '> a **b *').
      final m = _build(src, cursorOffset: 9);
      expect(m.textSpan.toPlainText(), 'a **b *c* d** e');
      expect(m.blockquoteSlots, hasLength(1),
          reason: 'marker must stay collapsed — only the inline chain '
              'reveals, not the whole line (regression test for #345)');
    });

    test(
        'cursor inside the bold-but-not-italic region reveals only the '
        'bold chain — the "> " marker stays collapsed', () {
      // 'b' at source offset 6.
      final m = _build(src, cursorOffset: 6);
      expect(m.textSpan.toPlainText(), 'a **b *c* d** e');
      expect(m.blockquoteSlots, hasLength(1));
    });

    test(
        'cursor directly on the marker reveals the raw "> " prefix; the '
        'border-stripe slot disappears while it does', () {
      final m = _build(src, cursorOffset: 1);
      expect(m.textSpan.toPlainText(), '> a b c d e');
      expect(m.blockquoteSlots, isEmpty,
          reason: 'a revealed marker is raw source text, not a slot');
    });

    test(
        'cursor at the marker\'s own end boundary (inclusive) still reveals '
        'the marker', () {
      // markerEnd = block.start + openDelimLen = 0 + 2 = 2, the boundary
      // between '> ' and 'a'. Same inclusive >=/<= boundary convention as
      // every other element's reveal check.
      final m = _build(src, cursorOffset: 2);
      expect(m.textSpan.toPlainText(), '> a b c d e');
      expect(m.blockquoteSlots, isEmpty);
    });

    test(
        'cursor one past the marker\'s end boundary no longer reveals the '
        'marker', () {
      final m = _build(src, cursorOffset: 3);
      expect(m.textSpan.toPlainText(), 'a b c d e');
      expect(m.blockquoteSlots, hasLength(1));
    });
  });
}
