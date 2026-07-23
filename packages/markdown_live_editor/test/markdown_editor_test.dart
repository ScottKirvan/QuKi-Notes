import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_render_editor.dart';

Widget _buildEditor({
  required String initialValue,
  MarkdownEditorController? controller,
  ValueChanged<String>? onChanged,
  bool autofocus = false,
  Future<Uint8List?> Function(String path)? imageLoader,
  void Function(String url)? onLinkTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MarkdownEditor(
        initialValue: initialValue,
        controller: controller,
        onChanged: onChanged,
        autofocus: autofocus,
        imageLoader: imageLoader,
        onLinkTap: onLinkTap,
      ),
    ),
  );
}

void main() {
  group('MarkdownEditorController — currentValue', () {
    testWidgets('currentValue returns initialValue before any edits',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      expect(controller.currentValue, 'hello world');
    });

    testWidgets('currentValue returns empty string when no editor attached',
        (tester) async {
      final controller = MarkdownEditorController();
      expect(controller.currentValue, '');
    });
  });

  group('MarkdownEditorController — setValue', () {
    testWidgets('setValue updates currentValue', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller.setValue('updated text');
      await tester.pump();

      expect(controller.currentValue, 'updated text');
    });

    testWidgets('setValue resets cursor to 0', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'abc',
        controller: controller,
      ));

      controller.setValue('new content');
      await tester.pump();

      expect(controller.currentValue, 'new content');
      // Verify selection is at offset 0 by using setSelectionForTesting to
      // confirm the controller state is readable after setValue.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 2));
      await tester.pump();
      expect(controller.currentValue, 'new content');
    });

    testWidgets('setValue is safe when value is unchanged', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'same',
        controller: controller,
      ));

      controller.setValue('same');
      await tester.pump();

      expect(controller.currentValue, 'same');
    });
  });

  group('MarkdownEditorController — plainTextMode', () {
    test('plainTextMode defaults to false', () {
      final controller = MarkdownEditorController();
      expect(controller.plainTextMode, isFalse);
    });

    testWidgets('togglePlainTextMode switches between styled and raw',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      expect(controller.plainTextMode, isFalse);

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.plainTextMode, isTrue);

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.plainTextMode, isFalse);
    });

    testWidgets('content is preserved across plain-text toggle',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text',
        controller: controller,
      ));

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');

      controller.togglePlainTextMode();
      await tester.pump();
      expect(controller.currentValue, 'some text');
    });

    testWidgets(
        'togglePlainTextMode changes rendered output: bold markers visible in plain-text mode',
        (tester) async {
      // Bug C regression: toggling plain-text mode must change what QuikiRenderEditor
      // actually renders. In styled mode "**bold**" collapses to "bold" (4 chars).
      // In plain-text mode it must display all 8 source characters unchanged.
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '**bold**',
        controller: controller,
      ));
      await tester.pump();

      // Helper: find the QuikiRenderEditor and read its current rendered length.
      QuikiRenderEditor renderEditor() {
        final ro = tester
            .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
        return ro;
      }

      // Styled mode: delimiters collapsed → rendered text is "bold" (4 chars).
      expect(controller.plainTextMode, isFalse);
      expect(renderEditor().renderModel.renderedLength, 4,
          reason:
              'styled mode: "**bold**" should collapse to "bold" (4 chars)');

      // Switch to plain-text mode.
      controller.togglePlainTextMode();
      await tester.pump();

      expect(controller.plainTextMode, isTrue);
      // Plain-text mode: no markdown processing → all 8 source chars visible.
      expect(renderEditor().renderModel.renderedLength, 8,
          reason:
              'plain-text mode: "**bold**" should render all 8 source chars');

      // Switch back to styled mode.
      controller.togglePlainTextMode();
      await tester.pump();

      expect(controller.plainTextMode, isFalse);
      expect(renderEditor().renderModel.renderedLength, 4,
          reason:
              'back to styled mode: "**bold**" should collapse again to 4 chars');
    });
  });

  group('MarkdownEditorController — hasActiveBlock', () {
    test('hasActiveBlock is false when no editor is attached', () {
      final controller = MarkdownEditorController();
      expect(controller.hasActiveBlock, isFalse);
    });

    testWidgets('hasActiveBlock reflects FocusNode.hasFocus', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      // No focus yet.
      expect(controller.hasActiveBlock, isFalse);

      // Focus the editor via requestFocus().
      controller.requestFocus();
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });

    testWidgets('focusFirstBlock focuses the editor', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      expect(controller.hasActiveBlock, isFalse);

      controller.focusFirstBlock();
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });

    testWidgets('requestFocus focuses the editor', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      expect(controller.hasActiveBlock, isTrue);
    });
  });

  group('MarkdownEditor — widget structure', () {
    testWidgets('renders a MarkdownEditor with content', (tester) async {
      await tester.pumpWidget(_buildEditor(initialValue: 'hello'));

      expect(find.byType(MarkdownEditor), findsOneWidget);
    });

    testWidgets('controller detaches on dispose', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'before dispose',
        controller: controller,
      ));

      expect(controller.currentValue, 'before dispose');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(controller.currentValue, '');
    });
  });

  group('MarkdownEditor — onChanged', () {
    testWidgets('fires onChanged when text is edited via IME', (tester) async {
      final changes = <String>[];
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
        onChanged: changes.add,
      ));

      controller.requestFocus();
      await tester.pump();

      // Simulate IME input by updating via the registered TextInputClient.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'new text',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();

      expect(changes, contains('new text'));
    });

    testWidgets('does not fire onChanged on setValue (programmatic update)',
        (tester) async {
      final controller = MarkdownEditorController();
      final changes = <String>[];

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
        onChanged: changes.add,
      ));

      controller.setValue('programmatic');
      await tester.pump();

      expect(changes, isEmpty);
    });
  });

  group('MarkdownEditorController — wrapSelection', () {
    testWidgets('wraps selected text with bold markers', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 6, extentOffset: 11));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, 'hello **world**');
    });

    testWidgets('inserts markers at cursor when no selection', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.wrapSelection('_', '_');
      await tester.pump();

      expect(controller.currentValue, 'hello__');
    });

    testWidgets(
        'places cursor between delimiters (not after suffix) when no text selected',
        (tester) async {
      // Regression: wrapSelection with collapsed cursor used to land the cursor
      // after the closing delimiter. It should land between prefix and suffix so
      // the user can type immediately inside the wrapped pair.
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      // Text: h e l l o * * * *
      //       0 1 2 3 4 5 6 7 8
      // Cursor must be at 7 — between opening ** (5–6) and closing ** (7–8).
      expect(controller.currentValue, 'hello****');
      expect(
        controller.selectionForTesting,
        const TextSelection.collapsed(offset: 7),
        reason: 'cursor must land between delimiters, not after closing suffix',
      );
    });

    testWidgets('wraps with strikethrough markers', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      controller.wrapSelection('~~', '~~');
      await tester.pump();

      expect(controller.currentValue, '~~word~~');
    });
  });

  group('MarkdownEditorController — toggleLinePrefix', () {
    testWidgets('adds heading prefix when absent', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'my heading',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, '# my heading');
    });

    testWidgets('removes heading prefix when present', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '# my heading',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'my heading');
    });

    testWidgets('operates on the correct line in multi-line text',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'line one\nline two\nline three',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 12));
      await tester.pump();

      controller.toggleLinePrefix('# ');
      await tester.pump();

      expect(controller.currentValue, 'line one\n# line two\nline three');
    });

    testWidgets('adds task prefix when absent', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'do the thing',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      controller.toggleLinePrefix('- [ ] ');
      await tester.pump();

      expect(controller.currentValue, '- [ ] do the thing');
    });
  });

  group('MarkdownEditorController — toggleUnorderedList', () {
    testWidgets('adds "- " prefix when line has no list marker',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'plain item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, '- plain item');
    });

    testWidgets('removes "- " prefix when already present', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '- plain item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'plain item');
    });

    testWidgets('strips full task list prefix when toggling off',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '- [ ] task item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      await tester.pump();

      controller.toggleUnorderedList();
      await tester.pump();

      expect(controller.currentValue, 'task item');
    });
  });

  group('MarkdownEditorController — toggleOrderedList', () {
    testWidgets('adds "1. " prefix when line has no ordered marker',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'first item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, '1. first item');
    });

    testWidgets('removes ordered prefix regardless of number', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '3. third item',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      controller.toggleOrderedList();
      await tester.pump();

      expect(controller.currentValue, 'third item');
    });
  });

  group('MarkdownEditorController — saved selection (toolbar focus loss)', () {
    testWidgets(
        'wrapSelection with valid selection [0,4] on "word" produces "**word**"'
        ' — regression: toolbar bold no-op', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'word',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**');
    });

    testWidgets(
        'wrapSelection falls back to saved selection when tc.selection is invalid'
        ' — regression: toolbar no-op on focus loss', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: MarkdownEditor(
                  initialValue: 'word',
                  controller: controller,
                ),
              ),
              const TextField(key: Key('other')),
            ],
          ),
        ),
      ));

      // Focus the editor and set a selection of [0, 4].
      controller.requestFocus();
      await tester.pump();
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();
      // _savedSelection is now [0, 4].

      // Move focus to the other TextField — simulates toolbar button stealing
      // focus before onPressed fires.
      await tester.tap(find.byKey(const Key('other')));
      await tester.pump();

      // wrapSelection must use saved selection [0,4] and wrap correctly.
      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**word**',
          reason:
              'wrapSelection must use saved selection [0,4] when tc.selection is invalid after focus loss');
    });
  });

  // ---------------------------------------------------------------------------
  // ADR-31 Stage 1 — new tests required by the task brief
  // ---------------------------------------------------------------------------

  group('ADR-31 Stage 1 — QuikiEditor parity', () {
    testWidgets('typing via IME inserts text into controller', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, 'hello');
    });

    testWidgets('backspace via IME removes last character', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'abc',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      // Simulate IME sending the post-backspace state.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();

      expect(controller.currentValue, 'ab');
    });

    testWidgets('setValue replaces buffer and controller reports new content',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'old content',
        controller: controller,
      ));

      controller.setValue('new content');
      await tester.pump();

      expect(controller.currentValue, 'new content');
    });

    testWidgets(
        'wrapSelection with selection [0,5] on "hello world" produces "**hello** world"',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 5));
      await tester.pump();

      controller.wrapSelection('**', '**');
      await tester.pump();

      expect(controller.currentValue, '**hello** world');
    });

    testWidgets('requestFocus gives the editor focus', (tester) async {
      final controller = MarkdownEditorController();
      final focusNode = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(
            initialValue: 'hello',
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ));

      expect(focusNode.hasFocus, isFalse);

      controller.requestFocus();
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);

      focusNode.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 5 — imageLoader widget-level tests
  // ---------------------------------------------------------------------------

  group('MarkdownEditor — imageLoader (Stage 5)', () {
    testWidgets(
        'imageLoader returning null: collapsed image line shows no source-text characters',
        (tester) async {
      // When imageLoader returns null the render model should still produce
      // no rendered chars for the image line (placeholder rect is painted,
      // raw markdown is not visible as text).
      const imageSource = '![alt](img.png)';
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: imageSource,
        controller: controller,
        imageLoader: (_) async => null,
      ));
      await tester.pump();

      // Find the render object and verify the image chars are not in the
      // rendered output — renderedLength should be 0 (no text chars emitted).
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.renderedLength, 0,
          reason:
              'collapsed image line must produce no rendered text characters');
      expect(ro.renderModel.imageSlots, hasLength(1),
          reason: 'one image slot must be registered for the image line');
    });

    testWidgets(
        'imageLoader returning valid bytes: no error thrown, widget renders normally',
        (tester) async {
      // A minimal 1x1 transparent PNG so the decode path can complete.
      // This is the smallest valid PNG (67 bytes).
      const minimalPng = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // 8-bit RGBA
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT length + type
        0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00, // IDAT data (zlib)
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, // IDAT continued
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND length + type
        0x42, 0x60, 0x82, // IEND CRC
      ];

      final controller = MarkdownEditorController();

      // Wrap in expectLater to catch any errors during the image decode.
      await tester.pumpWidget(_buildEditor(
        initialValue: '![test](test.png)',
        controller: controller,
        imageLoader: (_) async => Uint8List.fromList(minimalPng),
      ));
      // Pump several times to allow async image load to complete.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // If we get here without throwing, the test passes.
      expect(find.byType(MarkdownEditor), findsOneWidget);
    });

    testWidgets(
        'cursor moved onto image line: raw source "![alt](path)" becomes visible',
        (tester) async {
      // When the cursor is placed inside the image element, the element is
      // revealed and the raw markdown source should be visible in the rendered
      // output (renderedLength includes the source chars).
      const imageSource = '![alt](img.png)';
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: imageSource,
        controller: controller,
        imageLoader: (_) async => null,
      ));
      await tester.pump();

      // Initially: image collapsed → no rendered chars.
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.renderedLength, 0);

      // Place cursor inside the image element (offset 0 is inside the element).
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      // With cursor at 0 (inside the image element), the element is revealed.
      expect(ro.renderModel.renderedLength, imageSource.length,
          reason:
              'revealed image element must expose all source chars as rendered text');
      // No image slot when revealed — raw text takes over.
      expect(ro.renderModel.imageSlots, isEmpty,
          reason: 'revealed image has no image slot');
    });
  });

  // ---------------------------------------------------------------------------
  // Stage 6 — onLinkTap widget-level tests
  // ---------------------------------------------------------------------------

  group('MarkdownEditor — onLinkTap (Stage 6)', () {
    testWidgets('collapsed link: linkSlots populated and url is correct',
        (tester) async {
      // Verify that the render model exposes a link slot with the correct URL
      // when the source contains a collapsed link.
      const source = '[Go](https://go.dev)';
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();

      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.linkSlots, hasLength(1));
      expect(ro.renderModel.linkSlots[0].element.url, 'https://go.dev');
    });

    testWidgets('cursor inside link: link is revealed, linkSlots is empty',
        (tester) async {
      // When the cursor is inside the link, the element is revealed and
      // linkSlots should be empty (revealed links are not tappable for URL open).
      const source = '[Go](https://go.dev)';
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: source,
        controller: controller,
      ));
      await tester.pump();

      // Place cursor inside the link (offset 1 = 'G').
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      await tester.pump();

      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.linkSlots, isEmpty,
          reason: 'revealed link should not appear in linkSlots');
    });

    testWidgets('onLinkTap wired: callback not called on plain text tap',
        (tester) async {
      // When the source contains only plain text, tapping should not call
      // onLinkTap regardless of position.
      final tappedUrls = <String>[];

      await tester.pumpWidget(_buildEditor(
        initialValue: 'plain text no links',
        onLinkTap: tappedUrls.add,
      ));
      await tester.pump();

      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.linkSlots, isEmpty);
      expect(tappedUrls, isEmpty);
    });

    testWidgets(
        'onLinkTap: null callback accepted — no error when link is in source',
        (tester) async {
      // When onLinkTap is null, the widget must not throw on construction or
      // during a render model build that contains link slots.
      const source = '[Go](https://go.dev)';
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: source,
        controller: controller,
        // onLinkTap intentionally omitted (null).
      ));
      await tester.pump();

      // No error, link slots still populated.
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.linkSlots, hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  // Blockquote stripe paint smoke tests (ADR-33 Stage 4, blockquote-indent
  // round). The left border stripe's vertical extent is now derived from
  // TextPainter.getBoxesForSelection() over the run's rendered content span.
  // These pump real blockquotes through a full paint pass and assert no
  // exception is thrown — guarding the new geometry against edge cases
  // (empty content, multi-line runs, wrapped lines). They do NOT assert exact
  // stripe pixel bounds: the widget-test font renders placeholder boxes, so
  // fine vertical text-metric alignment is not reliably verifiable here.
  // -------------------------------------------------------------------------
  group('MarkdownEditor — blockquote stripe paint smoke tests', () {
    testWidgets('single collapsed blockquote paints without error',
        (tester) async {
      await tester.pumpWidget(_buildEditor(initialValue: '> quoted text'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.blockquoteSlots, hasLength(1));
    });

    testWidgets('empty blockquote paints without error', (tester) async {
      await tester.pumpWidget(_buildEditor(initialValue: '> '));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.blockquoteSlots, hasLength(1));
    });

    testWidgets('multi-line blockquote run paints without error',
        (tester) async {
      await tester.pumpWidget(
        _buildEditor(initialValue: '> line one\n> line two\n> line three'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final ro = tester
          .renderObject<QuikiRenderEditor>(find.byType(QuikiRenderWidget));
      expect(ro.renderModel.blockquoteSlots, hasLength(3));
    });

    testWidgets('long (wrapping) blockquote paints without error',
        (tester) async {
      await tester.pumpWidget(_buildEditor(
        initialValue:
            '> ${'this is a deliberately long quoted line that should wrap ' * 3}',
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Tab key (ADR-34 Fix 2 / block_indentation.md). Before this fix,
  // QuikiEditor's _handleKeyEvent had no case for LogicalKeyboardKey.tab, so
  // it fell through to KeyEventResult.ignored — which let Flutter's default
  // focus-traversal system consume the keystroke before it ever reached the
  // text buffer. This is scoped strictly to "let the raw keystroke through
  // as a literal '\t' character" — NOT Tab/Shift+Tab interactive
  // indent/dedent, which remains #77, a separate future feature. Uses a real
  // tester.sendKeyEvent through the actual Focus tree (rather than a
  // ForTesting wrapper that calls the handler method directly), since the
  // bug under test — traversal swallowing the key before it reaches the
  // handler — can only be exercised through the real dispatch path.
  // -------------------------------------------------------------------------
  group('QuikiEditor — Tab key (ADR-34 Fix 2)', () {
    testWidgets(
        'pressing Tab with a collapsed cursor inserts a literal tab '
        'character at the cursor and does not move focus away from the '
        'editor', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'ab',
        controller: controller,
      ));

      controller.setSelectionForTesting(const TextSelection.collapsed(
        offset: 1,
      ));
      controller.requestFocus();
      await tester.pump();
      expect(controller.hasActiveBlock, isTrue,
          reason: 'editor must be focused before the key press for this '
              'test to be meaningful');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.currentValue, 'a\tb',
          reason: 'Tab must insert a literal tab character at the cursor, '
              'not be silently swallowed by focus traversal');
      expect(controller.hasActiveBlock, isTrue,
          reason: 'the editor must still hold focus after Tab — if '
              'traversal had consumed the key, focus would have moved '
              'away');
    });

    testWidgets(
        'pressing Tab with an active (non-collapsed) selection replaces '
        'the selection with a tab character', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      controller.setSelectionForTesting(
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      controller.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(controller.currentValue, '\t world',
          reason: 'Tab must replace the active selection with a tab '
              'character — the same selection-replace semantics ordinary '
              'inserted text uses (see _pasteFromClipboard)');
    });

    testWidgets('Shift+Tab is left unhandled (out of scope for this fix)',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'ab',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 1));
      controller.requestFocus();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.currentValue, 'ab',
          reason: 'Shift+Tab must not insert a tab character — it is left '
              'to default (reverse) focus-traversal behavior, out of scope '
              'for this fix');
    });
  });
}
