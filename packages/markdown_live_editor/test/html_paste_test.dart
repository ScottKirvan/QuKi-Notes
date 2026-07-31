import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/html_paste.dart';
import 'package:markdown_live_editor/src/quiki_editor.dart';

// ---------------------------------------------------------------------------
// Clipboard mock (plain-text fallback path)
//
// Same pattern as clipboard_toolbar_test.dart: registers a fake method-
// channel handler for SystemChannels.platform so Clipboard.getData /
// Clipboard.setData work inside testWidgets.
// ---------------------------------------------------------------------------

class _MockClipboard {
  Map<String, dynamic>? _data;

  Future<Object?> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.getData':
        return _data;
      case 'Clipboard.setData':
        _data = (call.arguments as Map).cast<String, dynamic>();
        return null;
      case 'Clipboard.hasStrings':
        final text = _data?['text'] as String?;
        return <String, bool>{'value': text != null && text.isNotEmpty};
    }
    return null;
  }

  void reset() => _data = null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
  ValueChanged<String>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
        onChanged: onChanged,
      ),
    ),
  );
}

QuikiEditorState _editorState(WidgetTester tester) =>
    tester.state<QuikiEditorState>(find.byType(QuikiEditor));

/// Installs a fake HTML clipboard reader for the duration of a test.
/// [html] null means "no HTML representation available" — the same signal
/// super_clipboard's real reader sends when Formats.htmlText can't be
/// provided.
void _setClipboardHtml(String? html) {
  QuikiEditorState.debugClipboardHtmlReader = () async => html;
}

void main() {
  final mockClipboard = _MockClipboard();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      mockClipboard.handleMethodCall,
    );
    mockClipboard.reset();
    // Default: no HTML representation on the clipboard, matching a platform
    // with nothing (or only plain text) copied. Individual tests override.
    _setClipboardHtml(null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    // Restore the real super_clipboard-backed reader so no test leaks state.
    QuikiEditorState.debugClipboardHtmlReader = null;
  });

  // ---------------------------------------------------------------------
  // convertHtmlToMarkdown — pure conversion, no widget tree needed.
  // ---------------------------------------------------------------------

  group('convertHtmlToMarkdown', () {
    test(
        'bold + italic + header + link convert to GFM syntax MdParser '
        'recognizes', () {
      const html = '<h2>Title</h2>'
          '<p>This is <b>bold</b> and <i>italic</i> text with a '
          '<a href="https://example.com">link</a>.</p>';
      final md = convertHtmlToMarkdown(html);

      expect(md, contains('## Title'),
          reason: 'headingStyle must be forced to atx — MdParser has no '
              'setext support');
      expect(md, contains('**bold**'));
      expect(md, contains('*italic*'));
      expect(md, contains('[link](https://example.com)'));

      // Round-trip through MdParser: every element must actually be
      // recognized, not just look like markdown.
      final elements = MdParser.parse(md);
      expect(elements.any((e) => e.kind == MdElKind.h2), isTrue,
          reason: 'the pasted heading must render as a heading');
      expect(elements.any((e) => e.kind == MdElKind.bold), isTrue,
          reason: 'the pasted bold text must render as bold');
      expect(elements.any((e) => e.kind == MdElKind.italic), isTrue,
          reason: 'the pasted italic text must render as italic');
      expect(elements.any((e) => e.kind == MdElKind.link), isTrue,
          reason: 'the pasted link must render as a link');
    });

    test('unordered list converts to a ul MdParser recognizes', () {
      const html = '<ul><li>First</li><li>Second</li></ul>';
      final md = convertHtmlToMarkdown(html);

      final elements = MdParser.parse(md);
      final ulElements = elements.where((e) => e.kind == MdElKind.ul);
      expect(ulElements.length, 2,
          reason: 'both list items must be recognized as ul elements');
    });

    test('checkbox list converts to GFM task-list syntax MdParser recognizes',
        () {
      const html = '<ul>'
          '<li><input type="checkbox"> Buy milk</li>'
          '<li><input type="checkbox" checked> Walk dog</li>'
          '</ul>';
      final md = convertHtmlToMarkdown(html);

      expect(md, contains('- [ ] Buy milk'),
          reason: 'unchecked box must convert to the exact 6-char marker '
              'MdParser requires, not html2md\'s default wider padding');
      expect(md, contains('- [x] Walk dog'),
          reason: 'checked box must convert to the checked marker');

      final elements = MdParser.parse(md);
      expect(elements.any((e) => e.kind == MdElKind.checkboxUnchecked), isTrue,
          reason: 'the pasted unchecked box must render as a checkbox');
      expect(elements.any((e) => e.kind == MdElKind.checkboxChecked), isTrue,
          reason: 'the pasted checked box must render as a checked checkbox');
    });

    test(
        'table converts to real | -delimited markdown table syntax, not '
        'flattened prose', () {
      const html = '<table>'
          '<thead><tr><th>Name</th><th>Age</th></tr></thead>'
          '<tbody>'
          '<tr><td>Alice</td><td>30</td></tr>'
          '<tr><td>Bob</td><td>25</td></tr>'
          '</tbody>'
          '</table>';
      final md = convertHtmlToMarkdown(html);

      expect(md, contains('| Name | Age |'));
      expect(md, contains('| Alice | 30 |'));
      expect(md, contains('| Bob | 25 |'));
      // A separator row (---) must be present, marking it as a real GFM
      // table header, not just pipe-delimited-looking prose.
      expect(md, matches(RegExp(r'\|\s*-+\s*\|\s*-+\s*\|')));
    });

    test('code block converts to fenced code markdown syntax', () {
      const html = '<pre><code class="language-dart">'
          'void main() {\n  print(\'hi\');\n}'
          '</code></pre>';
      final md = convertHtmlToMarkdown(html);

      expect(md, contains('```'),
          reason: 'codeBlockStyle must be forced to fenced — MdParser has '
              'no indented-code support');
      expect(md, contains('void main()'));
      expect(md, isNot(contains('    void main()')),
          reason: 'must not fall back to html2md\'s default 4-space '
              'indented code style');
    });

    test(
        'img tag converts to ![alt](url) with the original source URL, no '
        'download attempt', () {
      const html = '<img src="https://example.com/photo.png" alt="A photo">';
      final md = convertHtmlToMarkdown(html);

      expect(md.trim(), '![A photo](https://example.com/photo.png)',
          reason: 'the original remote URL must be preserved verbatim — no '
              'fetch/download/embed attempt (deferred to #246/#247)');
    });
  });

  // ---------------------------------------------------------------------
  // _pasteFromClipboard — integration through the real buffer-update path.
  // ---------------------------------------------------------------------

  group('_pasteFromClipboard — HTML clipboard integration', () {
    testWidgets(
        'HTML reader throws (e.g. native plugin channel unavailable): '
        'falls through to plain text instead of crashing paste',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'helo world',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      QuikiEditorState.debugClipboardHtmlReader =
          () async => throw StateError('native channel unavailable');
      await Clipboard.setData(const ClipboardData(text: 'l'));

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      await tester.pump();

      expect(controller.currentValue, 'hello world',
          reason: 'a thrown error from the HTML reader must degrade '
              'gracefully to plain-text paste, not surface as a crash');
    });

    testWidgets(
        'no HTML representation on clipboard: falls through to plain text, '
        'byte-identical to pre-ADR-35 behavior', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'helo world',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      // No HTML representation available (the default from setUp).
      await Clipboard.setData(const ClipboardData(text: 'l'));

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      await tester.pump();

      expect(controller.currentValue, 'hello world',
          reason: 'with no HTML on the clipboard, paste must behave exactly '
              'as plain-text paste always has');
    });

    testWidgets(
        'HTML representation present: converts and inserts markdown, not '
        'the plain-text fallback', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      _setClipboardHtml('<p>Hello <b>world</b></p>');
      // Plain-text fallback would insert this instead if HTML were ignored.
      await Clipboard.setData(const ClipboardData(text: 'PLAIN FALLBACK'));

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      await tester.pump();

      expect(controller.currentValue, contains('**world**'),
          reason: 'HTML on the clipboard must take priority over plain text');
      expect(controller.currentValue, isNot(contains('PLAIN FALLBACK')));
    });

    testWidgets(
        'pasting over an active selection replaces it, same as '
        'plain-text paste', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'aaa bbb ccc',
        controller: controller,
      ));

      // Select "bbb" (offsets 4-7).
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 4, extentOffset: 7));
      await tester.pump();

      _setClipboardHtml('<b>XXX</b>');

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      await tester.pump();

      expect(controller.currentValue, 'aaa **XXX** ccc',
          reason: 'paste over a selection must replace the selected range, '
              'exactly as plain-text paste does');
    });

    testWidgets(
        'paste behavior is identical whether plainTextMode is on or off',
        (tester) async {
      final controllerOff = MarkdownEditorController();
      final controllerOn = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'x',
        controller: controllerOff,
      ));
      controllerOff
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      _setClipboardHtml('<p>Hello <b>world</b></p>');
      _editorState(tester).pasteFromClipboardForTesting();
      await tester.pump();
      final resultPlainOff = controllerOff.currentValue;

      // Force a full unmount before rebuilding with a different controller —
      // MarkdownEditorController only attaches in initState, so reusing the
      // same widget position with a different controller and no disposal in
      // between would silently leave controllerOn detached (a known
      // pumpWidget-reuse gotcha in this test suite).
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
      await tester.pump();

      // Rebuild fresh with plain-text mode toggled on before pasting.
      await tester.pumpWidget(_buildEditor(
        initialValue: 'x',
        controller: controllerOn,
      ));
      controllerOn.togglePlainTextMode();
      controllerOn
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      _editorState(tester).pasteFromClipboardForTesting();
      await tester.pump();
      final resultPlainOn = controllerOn.currentValue;

      expect(resultPlainOn, resultPlainOff,
          reason: 'plainTextMode controls rendering of the existing buffer, '
              'not what paste writes into it — the inserted text must be '
              'identical either way');
      expect(resultPlainOn, contains('**world**'));
    });
  });
}
