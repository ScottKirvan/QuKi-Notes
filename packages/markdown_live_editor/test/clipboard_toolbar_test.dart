import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/quiki_editor.dart';

// ---------------------------------------------------------------------------
// Clipboard mock
//
// Registers a fake method-channel handler for SystemChannels.platform so
// Clipboard.getData / Clipboard.setData work inside testWidgets (FakeAsync).
// Without this the platform channel calls either hang or return null.
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

// Retrieves the QuikiEditorState nested inside the widget tree.
QuikiEditorState _editorState(WidgetTester tester) =>
    tester.state<QuikiEditorState>(find.byType(QuikiEditor));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final mockClipboard = _MockClipboard();

  setUp(() {
    // Install the mock clipboard handler before each test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      mockClipboard.handleMethodCall,
    );
    mockClipboard.reset();
  });

  tearDown(() {
    // Remove the mock after each test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // -------------------------------------------------------------------------
  // Clipboard operation correctness
  // -------------------------------------------------------------------------

  group('Clipboard operations — correctness', () {
    testWidgets(
        '_copySelection: buffer unchanged after copy (copy is non-destructive)',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      // Select "world" (offsets 6–11) and copy.
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 6, extentOffset: 11));
      await tester.pump();

      final state = _editorState(tester);
      state.copySelectionForTesting();
      await tester.pump();

      // Buffer must not be changed by a copy operation.
      expect(controller.currentValue, 'hello world',
          reason: '_copySelection must not mutate the source buffer');
    });

    testWidgets('_copySelection: correct source text written to clipboard',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      // Select "world" (offsets 6–11) and copy.
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 6, extentOffset: 11));
      await tester.pump();

      final state = _editorState(tester);
      state.copySelectionForTesting();
      // Allow the Clipboard.setData platform call to resolve.
      await tester.pump();

      // Read what landed on the mock clipboard.
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipData?.text, 'world',
          reason:
              '_copySelection must write the selected source text to the clipboard');
    });

    testWidgets(
        '_copySelection: no-op when selection is collapsed — clipboard unchanged',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello',
        controller: controller,
      ));

      // Pre-load clipboard with known content.
      await Clipboard.setData(const ClipboardData(text: 'before'));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      final state = _editorState(tester);
      state.copySelectionForTesting();
      await tester.pump();

      // Clipboard must be unchanged since there was no selection to copy.
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipData?.text, 'before',
          reason: '_copySelection must be a no-op when selection is collapsed');
    });

    testWidgets('_cutSelection: removes selected range from buffer',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      // Select "hello " (offsets 0–6).
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 6));
      await tester.pump();

      final state = _editorState(tester);
      state.cutSelectionForTesting();
      await tester.pump();

      // The selected text must be removed from the buffer.
      expect(controller.currentValue, 'world',
          reason:
              '_cutSelection must delete the selected range from the buffer');
    });

    testWidgets(
        '_cutSelection: copies correct text to clipboard AND removes from buffer',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      // Select "hello " (offsets 0–6).
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 6));
      await tester.pump();

      final state = _editorState(tester);
      state.cutSelectionForTesting();
      await tester.pump();

      // Buffer mutation.
      expect(controller.currentValue, 'world',
          reason: 'cut must delete the selected range');

      // Clipboard content.
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipData?.text, 'hello ',
          reason: 'cut must place the selected text on the clipboard');
    });

    testWidgets(
        '_pasteFromClipboard: inserts clipboard text at cursor position',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'helo world',
        controller: controller,
      ));

      // Place cursor at offset 3 (after "hel").
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      // Pre-load clipboard via mock.
      await Clipboard.setData(const ClipboardData(text: 'l'));

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      // Allow the Clipboard.getData future to complete.
      await tester.pump();

      expect(controller.currentValue, 'hello world',
          reason: 'pasted text must be inserted at cursor position');
    });

    testWidgets('_pasteFromClipboard: replaces selected range with clipboard',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'aaa bbb ccc',
        controller: controller,
      ));

      // Select "bbb" (offsets 4–7).
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 4, extentOffset: 7));
      await tester.pump();

      await Clipboard.setData(const ClipboardData(text: 'XXX'));

      final state = _editorState(tester);
      state.pasteFromClipboardForTesting();
      await tester.pump();

      expect(controller.currentValue, 'aaa XXX ccc',
          reason: 'paste over selection must replace the selected range');
    });

    testWidgets('_selectAll: selects full buffer — verified via wrap',
        (tester) async {
      final controller = MarkdownEditorController();
      const text = 'select me entirely';

      await tester.pumpWidget(_buildEditor(
        initialValue: text,
        controller: controller,
      ));

      // Place cursor mid-text first.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 5));
      await tester.pump();

      final state = _editorState(tester);
      state.selectAllForTesting();
      await tester.pump();

      // Content must be unchanged by selectAll.
      expect(controller.currentValue, text);

      // Verify selection spans the full text: wrapSelection must surround all.
      controller.wrapSelection('(', ')');
      await tester.pump();

      expect(controller.currentValue, '($text)',
          reason:
              'selectAll must select the entire buffer so wrapSelection covers it');
    });
  });

  // -------------------------------------------------------------------------
  // Toolbar state — widget-level
  // -------------------------------------------------------------------------

  group('Selection toolbar — state', () {
    testWidgets(
        'showToolbarForTesting: toolbar is visible after non-collapsed selection',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text here',
        controller: controller,
      ));

      // Set a non-collapsed selection.
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      final state = _editorState(tester);
      expect(state.isToolbarShown, isFalse,
          reason: 'toolbar must not be visible before it is shown');

      // Force show regardless of platform (test host is Windows/Linux).
      state.showToolbarForTesting();
      await tester.pump();

      expect(state.isToolbarShown, isTrue,
          reason: 'toolbar must be visible after showToolbarForTesting()');
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });

    testWidgets(
        'showToolbarForTesting: toolbar IS shown for a collapsed selection '
        '(paste unreachable fix)', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text',
        controller: controller,
      ));

      // Collapsed selection.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();

      expect(state.isToolbarShown, isTrue,
          reason: 'toolbar must appear for a collapsed selection so Paste is '
              'reachable via long-press on an empty line or between words');
    });

    testWidgets(
        'collapsed selection: toolbar shows only Paste and Select All — '
        'no Cut, no Copy', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();

      expect(state.isToolbarShown, isTrue);

      // There must be exactly 2 ContextMenuItemButton widgets: Paste and
      // Select All.  Cut and Copy must not be in the tree.
      expect(find.text('Paste'), findsOneWidget,
          reason: 'Paste must appear for a collapsed selection');
      expect(find.text('Select All'), findsOneWidget,
          reason: 'Select All must appear for a collapsed selection');
      expect(find.text('Cut'), findsNothing,
          reason: 'Cut must NOT appear when there is no selection to cut');
      expect(find.text('Copy'), findsNothing,
          reason: 'Copy must NOT appear when there is no selection to copy');
    });

    testWidgets(
        'non-collapsed selection: toolbar shows all 4 buttons '
        '(Cut, Copy, Paste, Select All)', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'some text here',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();

      expect(state.isToolbarShown, isTrue);
      expect(find.text('Cut'), findsOneWidget,
          reason: 'Cut must appear for a non-collapsed selection');
      expect(find.text('Copy'), findsOneWidget,
          reason: 'Copy must appear for a non-collapsed selection');
      expect(find.text('Paste'), findsOneWidget,
          reason: 'Paste must appear for a non-collapsed selection');
      expect(find.text('Select All'), findsOneWidget,
          reason: 'Select All must appear for a non-collapsed selection');
    });

    testWidgets('Select All re-shows toolbar (copy after Select All fix)',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'hello world',
        controller: controller,
      ));

      // Start with a collapsed selection.
      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 3));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();

      expect(state.isToolbarShown, isTrue,
          reason: 'toolbar must be visible before tapping Select All');

      // Tap the Select All button.
      await tester.tap(find.text('Select All'));
      await tester.pump();

      // The toolbar must re-appear with all 4 buttons (full selection).
      expect(state.isToolbarShown, isTrue,
          reason:
              'toolbar must re-appear after Select All so Copy is reachable');
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);
    });

    testWidgets('toolbar re-shown after Select All is dismissed by next tap',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'dismiss me',
        controller: controller,
      ));

      controller
          .setSelectionForTesting(const TextSelection.collapsed(offset: 0));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();

      // Tap Select All to re-show the toolbar.
      await tester.tap(find.text('Select All'));
      await tester.pump();
      expect(state.isToolbarShown, isTrue,
          reason: 'toolbar must be visible after Select All');

      // A subsequent tap must dismiss it. The pump is deliberately longer
      // than kDoubleTapTimeout: now that a double-tap recognizer shares this
      // GestureDetector's gesture arena (feat/selection-stage1),
      // TapGestureRecognizer cannot conclusively resolve — and so onTapDown
      // does not fire — until it's certain no second tap is coming, which
      // takes up to kDoubleTapTimeout. See selection_test.dart's doubleTapAt
      // doc comment for the full explanation; this is the same underlying
      // gesture-arena behavior, just observed from a single-tap test rather
      // than a double-tap one.
      await tester.tapAt(tester.getCenter(find.byType(MarkdownEditor)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.isToolbarShown, isFalse,
          reason: 'toolbar must be dismissed by _onTapDown after the re-show');
    });

    testWidgets('toolbar is dismissed on next tap', (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'tap to dismiss',
        controller: controller,
      ));

      // Set a non-collapsed selection and show the toolbar.
      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 3));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();
      expect(state.isToolbarShown, isTrue);

      // Simulate a tap anywhere in the editor — _onTapDown dismisses toolbar.
      // See the comment on the equivalent tapAt above (same file) for why
      // this pump must be longer than kDoubleTapTimeout now that a
      // double-tap recognizer shares the gesture arena.
      await tester.tapAt(tester.getCenter(find.byType(MarkdownEditor)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.isToolbarShown, isFalse,
          reason: 'toolbar must be dismissed by the next _onTapDown');
    });

    testWidgets('toolbar is dismissed on dispose — no leaked OverlayEntry',
        (tester) async {
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'disposed',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      final state = _editorState(tester);
      state.showToolbarForTesting();
      await tester.pump();
      expect(state.isToolbarShown, isTrue);

      // Replace widget tree — disposes the editor.
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())));
      await tester.pump();

      // Verify no toolbar overlay remains in the tree.
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing,
          reason: 'toolbar OverlayEntry must be removed on dispose');
    });

    testWidgets(
        'on desktop (test host): showToolbar() does NOT show toolbar — '
        '_isMobile guard', (tester) async {
      // The test host is Windows/Linux.  _isMobile returns false.
      // showToolbar() calls _showSelectionToolbar() without skipMobileCheck,
      // so it must return early — no toolbar appears.
      final controller = MarkdownEditorController();

      await tester.pumpWidget(_buildEditor(
        initialValue: 'desktop guard test',
        controller: controller,
      ));

      controller.setSelectionForTesting(
          const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();

      final state = _editorState(tester);
      // showToolbar() is the production path (called by TextInputClient).
      state.showToolbar();
      await tester.pump();

      // On desktop, no toolbar should appear.
      expect(state.isToolbarShown, isFalse,
          reason: 'toolbar must NOT appear on desktop — keyboard shortcuts '
              'cover clipboard on Windows/Linux');
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    });
  });
}
