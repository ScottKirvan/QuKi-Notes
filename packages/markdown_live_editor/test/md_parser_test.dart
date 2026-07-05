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
}
