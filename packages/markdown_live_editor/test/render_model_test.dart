import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

const _base = TextStyle(fontSize: 16.0, color: Color(0xFFFFFFFF));
const _syntax = Color(0x59FFFFFF);

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
    syntaxColor: _syntax,
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
        'bold revealed: cursor inside → identity mapping, delimiter spans use syntaxColor',
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

      // First TextSpan child should have syntaxColor (the '**' delimiters).
      final children = m.textSpan.children!;
      final firstSpan = children[0] as TextSpan;
      expect(firstSpan.text, '**');
      expect(firstSpan.style?.color, _syntax);
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

      // First span should be '# ' with syntaxColor.
      final children = m.textSpan.children!;
      final firstSpan = children[0] as TextSpan;
      expect(firstSpan.text, '# ');
      expect(firstSpan.style?.color, _syntax);
    });
  });
}
