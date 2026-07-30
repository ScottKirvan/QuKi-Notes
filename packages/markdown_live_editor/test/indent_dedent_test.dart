import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';
import 'package:markdown_live_editor/src/indent_dedent.dart';

// ---------------------------------------------------------------------------
// Interactive Indent/Dedent — ADR-34 Stage 4 (#77). See
// notes/dev/block_indentation.md → "Stage 4" for the full behaviour spec and
// packages/markdown_live_editor/lib/src/indent_dedent.dart for the
// implementation this exercises directly (pure functions, no widget tree
// needed for most of this coverage).
//
// A smaller widget-level group at the bottom proves: (a) the toolbar buttons
// and the Tab/Shift+Tab keys route through the exact same pure functions and
// so produce identical results, and (b) the full "type '-', press Enter,
// press Indent" workflow works end to end through the real widget.
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Indent — collapsed cursor, list items (ul / ol / checkbox).
  // -------------------------------------------------------------------------
  group('applyIndent — collapsed cursor, list items', () {
    void checkIndentPreservesRelativeCursor(
      String description,
      String source,
      int contentOffset,
    ) {
      test(
          '$description: cursor at content offset $contentOffset shifts by '
          'exactly the inserted marker length', () {
        final result = applyIndent(
          source,
          TextSelection.collapsed(offset: contentOffset),
        );
        expect(result.text, '\t$source');
        expect(
          result.selection,
          TextSelection.collapsed(offset: contentOffset + 1),
        );
      });
    }

    // ul: '- item' — content 'item' spans offsets 2..6.
    checkIndentPreservesRelativeCursor(
        'ul, cursor at content start', '- item', 2);
    checkIndentPreservesRelativeCursor(
        'ul, cursor at content middle', '- item', 4);
    checkIndentPreservesRelativeCursor(
        'ul, cursor at content end', '- item', 6);

    // ol: '1. item' — content 'item' spans offsets 3..7.
    checkIndentPreservesRelativeCursor(
        'ol, cursor at content start', '1. item', 3);
    checkIndentPreservesRelativeCursor(
        'ol, cursor at content middle', '1. item', 5);
    checkIndentPreservesRelativeCursor(
        'ol, cursor at content end', '1. item', 7);

    // checkbox unchecked: '- [ ] item' — content spans offsets 6..10.
    checkIndentPreservesRelativeCursor(
        'checkbox unchecked, cursor at content start', '- [ ] item', 6);
    checkIndentPreservesRelativeCursor(
        'checkbox unchecked, cursor at content middle', '- [ ] item', 8);
    checkIndentPreservesRelativeCursor(
        'checkbox unchecked, cursor at content end', '- [ ] item', 10);

    // checkbox checked: '- [x] item' — content spans offsets 6..10.
    checkIndentPreservesRelativeCursor(
        'checkbox checked, cursor at content start', '- [x] item', 6);
    checkIndentPreservesRelativeCursor(
        'checkbox checked, cursor at content middle', '- [x] item', 8);
    checkIndentPreservesRelativeCursor(
        'checkbox checked, cursor at content end', '- [x] item', 10);

    test('indenting a ul line increases MdParser-reported depth by one', () {
      final result =
          applyIndent('- item', const TextSelection.collapsed(offset: 4));
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ul);
      expect(els[0].indentLevel, 1);
    });

    test('indenting an ol line increases MdParser-reported depth by one', () {
      final result =
          applyIndent('1. item', const TextSelection.collapsed(offset: 5));
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.ol);
      expect(els[0].indentLevel, 1);
    });

    test('checkbox unchecked survives indent (state unchanged)', () {
      final result =
          applyIndent('- [ ] item', const TextSelection.collapsed(offset: 8));
      expect(result.text, '\t- [ ] item');
      final els = MdParser.parse(result.text);
      expect(els[0].kind, MdElKind.checkboxUnchecked);
    });

    test('checkbox checked survives indent (state unchanged)', () {
      final result =
          applyIndent('- [x] item', const TextSelection.collapsed(offset: 8));
      expect(result.text, '\t- [x] item');
      final els = MdParser.parse(result.text);
      expect(els[0].kind, MdElKind.checkboxChecked);
    });

    test('multiple consecutive indents nest a list item arbitrarily deep', () {
      var text = '- item';
      var sel = const TextSelection.collapsed(offset: 4);
      for (var i = 0; i < 5; i++) {
        final result = applyIndent(text, sel);
        text = result.text;
        sel = result.selection;
      }
      expect(text, '\t\t\t\t\t- item');
      final els = MdParser.parse(text);
      expect(els[0].indentLevel, 5);
    });
  });

  // -------------------------------------------------------------------------
  // Dedent — collapsed cursor, list items.
  // -------------------------------------------------------------------------
  group('applyDedent — collapsed cursor, list items', () {
    test('dedenting a depth-1 ul line returns to depth 0', () {
      final result =
          applyDedent('\t- item', const TextSelection.collapsed(offset: 5));
      expect(result.text, '- item');
      final els = MdParser.parse(result.text);
      expect(els[0].indentLevel, 0);
    });

    test('dedenting a 2-space-indented ul line returns to depth 0', () {
      final result =
          applyDedent('  - item', const TextSelection.collapsed(offset: 6));
      expect(result.text, '- item');
    });

    test(
        'dedent at level 0 is a no-op — text and selection are byte-'
        'identical to the input, not merely "doesn\'t crash"', () {
      const text = '- item';
      const sel = TextSelection.collapsed(offset: 4);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });

    test('checkbox checked state survives dedent', () {
      final result =
          applyDedent('\t- [x] item', const TextSelection.collapsed(offset: 9));
      expect(result.text, '- [x] item');
      final els = MdParser.parse(result.text);
      expect(els[0].kind, MdElKind.checkboxChecked);
    });

    test('checkbox unchecked state survives dedent', () {
      final result =
          applyDedent('\t- [ ] item', const TextSelection.collapsed(offset: 9));
      expect(result.text, '- [ ] item');
      final els = MdParser.parse(result.text);
      expect(els[0].kind, MdElKind.checkboxUnchecked);
    });

    test('indent then dedent round-trips back to the original text', () {
      const original = '- item';
      final indented =
          applyIndent(original, const TextSelection.collapsed(offset: 4));
      final dedented = applyDedent(indented.text, indented.selection);
      expect(dedented.text, original);
      expect(dedented.selection, const TextSelection.collapsed(offset: 4));
    });
  });

  // -------------------------------------------------------------------------
  // Plain paragraph lines.
  // -------------------------------------------------------------------------
  group('applyIndent / applyDedent — plain paragraph lines', () {
    test(
        'Indent on a plain paragraph inserts a literal tab at the line '
        'start, not at the cursor — deliberate divergence from the '
        'previously-shipped at-cursor Tab insert', () {
      final result =
          applyIndent('hello world', const TextSelection.collapsed(offset: 5));
      expect(result.text, '\thello world');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
    });

    test('Dedent removes a leading literal tab from a paragraph line', () {
      final result = applyDedent(
          '\thello world', const TextSelection.collapsed(offset: 6));
      expect(result.text, 'hello world');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
    });

    test('Dedent on a paragraph with no leading tab is a no-op', () {
      const text = 'hello world';
      const sel = TextSelection.collapsed(offset: 5);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });

    test('Indent on a blank line inserts a tab at its start', () {
      final result = applyIndent('', const TextSelection.collapsed(offset: 0));
      expect(result.text, '\t');
      expect(result.selection, const TextSelection.collapsed(offset: 1));
    });
  });

  // -------------------------------------------------------------------------
  // Headings and blockquotes — excluded; fall back to pre-existing
  // at-cursor-insert (Indent) / no-op (Dedent) behaviour, and MdParser must
  // still recognize the line afterward (recognition is not broken).
  // -------------------------------------------------------------------------
  group('applyIndent / applyDedent — headings and blockquotes (excluded)', () {
    test(
        'Indent on a heading line inserts a tab AT THE CURSOR, matching '
        'the pre-existing Tab behaviour byte-for-byte', () {
      final result =
          applyIndent('# my heading', const TextSelection.collapsed(offset: 5));
      expect(result.text, '# my \theading');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
      // Recognition must survive: still a single h1 element, not corrupted
      // into plain text.
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.h1);
    });

    test('Dedent on a heading line is a no-op', () {
      const text = '# my heading';
      const sel = TextSelection.collapsed(offset: 5);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });

    test(
        'Indent on a blockquote line inserts a tab AT THE CURSOR, matching '
        'the pre-existing Tab behaviour byte-for-byte', () {
      final result = applyIndent(
          '> quoted text', const TextSelection.collapsed(offset: 4));
      expect(result.text, '> qu\toted text');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.blockquote);
    });

    test('Dedent on a blockquote line is a no-op', () {
      const text = '> quoted text';
      const sel = TextSelection.collapsed(offset: 4);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });

    test(
        'Indent on a collapsed cursor with an active (non-collapsed) '
        'selection inside a heading replaces the selection, matching the '
        'pre-existing Tab behaviour', () {
      final result = applyIndent(
          '# hello world', const TextSelection(baseOffset: 2, extentOffset: 7));
      expect(result.text, '# \t world');
    });
  });

  // -------------------------------------------------------------------------
  // Block images — excluded for the same reason as headings/blockquotes
  // above: recognized only via a line prefix (`![`) / suffix (`)`), not the
  // whole line, so a tab inserted elsewhere is harmless. Falls back to the
  // pre-existing at-cursor-insert (Indent) / no-op (Dedent) behaviour, and
  // MdParser must still recognize the line afterward (recognition is not
  // broken).
  // -------------------------------------------------------------------------
  group('applyIndent / applyDedent — block images (excluded)', () {
    test(
        'Indent on a block-image line inserts a tab AT THE CURSOR, matching '
        'the pre-existing Tab behaviour byte-for-byte', () {
      final result = applyIndent(
          '![alt](path.png)', const TextSelection.collapsed(offset: 5));
      expect(result.text, '![alt\t](path.png)');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
      // Recognition must survive: still a single image element, not
      // corrupted into plain text.
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.image);
    });

    test('Dedent on a block-image line is a no-op', () {
      const text = '![alt](path.png)';
      const sel = TextSelection.collapsed(offset: 5);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });
  });

  // -------------------------------------------------------------------------
  // Horizontal rules — unlike headings/blockquotes/images, MdParser's
  // _isHrLine requires the ENTIRE line to consist of only the hr character
  // or plain spaces, so a tab inserted anywhere (start, middle, or end)
  // always breaks recognition. There is no cursor position where an
  // at-cursor tab insert is safe, so Indent is a no-op here too — text and
  // selection unchanged, same as Dedent.
  // -------------------------------------------------------------------------
  group('applyIndent / applyDedent — horizontal rules (excluded, no-op)', () {
    test('Indent on an hr line is a no-op', () {
      const text = '---';
      const sel = TextSelection.collapsed(offset: 1);
      final result = applyIndent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
      // Still recognized as hr — untouched, not corrupted.
      final els = MdParser.parse(result.text);
      expect(els, hasLength(1));
      expect(els[0].kind, MdElKind.hr);
    });

    test('Dedent on an hr line is a no-op', () {
      const text = '---';
      const sel = TextSelection.collapsed(offset: 1);
      final result = applyDedent(text, sel);
      expect(result.text, same(text));
      expect(result.selection, sel);
    });
  });

  // -------------------------------------------------------------------------
  // Multi-line selections.
  // -------------------------------------------------------------------------
  group('applyIndent / applyDedent — multi-line selections', () {
    test(
        'selection spanning list items at different depths shifts each by '
        'one level, preserving relative nesting', () {
      const source = '- top\n  - sub\n- top2';
      // Select the whole block.
      final result = applyIndent(
        source,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      expect(result.text, '\t- top\n\t  - sub\n\t- top2');

      final lines = result.text.split('\n');
      final topEls = MdParser.parse(lines[0]);
      final subEls = MdParser.parse(lines[1]);
      final top2Els = MdParser.parse(lines[2]);
      expect(topEls[0].indentLevel, 1);
      expect(subEls[0].indentLevel, 2);
      expect(top2Els[0].indentLevel, 1);
    });

    test(
        'selection spanning a heading, a list item, and a paragraph: '
        'heading is left alone, list item depth changes, paragraph gets a '
        'line-start tab', () {
      const source = '# Heading\n- item\nparagraph';
      final result = applyIndent(
        source,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      expect(result.text, '# Heading\n\t- item\n\tparagraph');
    });

    test(
        'selection touching zero eligible lines (heading + blockquote only) '
        'falls back to the pre-existing selection-replace-with-tab '
        'behaviour — regression guard', () {
      const source = '# Heading\n> Quote';
      final result = applyIndent(
        source,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      expect(result.text, '\t');
      expect(result.selection, const TextSelection.collapsed(offset: 1));
    });

    test(
        'Dedent on a selection touching zero eligible lines is a no-op '
        '(no meaningful selection-replace analogue for removal)', () {
      const source = '# Heading\n> Quote';
      final sel = TextSelection(baseOffset: 0, extentOffset: source.length);
      final result = applyDedent(source, sel);
      expect(result.text, same(source));
      expect(result.selection, sel);
    });

    test(
        'selection touching zero eligible lines (hr + block image only) '
        'falls back to the pre-existing selection-replace-with-tab '
        'behaviour — confirms hr/image are ineligible too, not just '
        'headings/blockquotes', () {
      const source = '---\n![alt](path.png)';
      final result = applyIndent(
        source,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      expect(result.text, '\t');
      expect(result.selection, const TextSelection.collapsed(offset: 1));
    });

    test(
        'Dedent on a multi-line list selection dedents each eligible line '
        'independently, clamping at level 0', () {
      const source = '- top\n  - sub';
      final result = applyDedent(
        source,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      // 'top' is already at level 0 (no-op for that line); 'sub' goes from
      // level 1 to level 0.
      expect(result.text, '- top\n- sub');
    });

    test('selection endpoints remap correctly across a multi-line indent', () {
      const source = '- top\n- bottom';
      // Select "top" (within the first line) through "bottom" (within the
      // second line): offsets 2-11 ("top\n- bott" — doesn't matter exactly
      // which characters, this is testing offset remapping through two
      // separate line-start insertions).
      final result = applyIndent(
        source,
        const TextSelection(baseOffset: 2, extentOffset: 11),
      );
      // Each of the two touched lines gets a tab at its own start: total
      // text grows by 2 characters, one inserted before offset 2 (shifting
      // it by 1) and one inserted before the second line's start (offset 6
      // in the original text, which is < 11, so it also shifts the end
      // offset).
      expect(result.text, '\t- top\n\t- bottom');
      expect(result.selection.baseOffset, 3);
      expect(result.selection.extentOffset, 13);
    });
  });

  // -------------------------------------------------------------------------
  // Ordered-list numbering recomputes correctly after Indent/Dedent — the
  // brief's invariant is that MdParser's existing depth-scoped numbering
  // logic needs zero new code; these tests assert the actual sequence
  // numbers, not just that parsing succeeds.
  // -------------------------------------------------------------------------
  group('ordered-list numbering after Indent/Dedent', () {
    test(
        'indenting the second item of a flat ol makes it a nested depth-1 '
        'sub-list starting its own sequence at 1', () {
      const source = '1. first\n2. second\n3. third';
      // Indent only the "second" line.
      final secondLineStart = source.indexOf('2. second');
      final result = applyIndent(
        source,
        TextSelection.collapsed(offset: secondLineStart + 3),
      );
      final els = MdParser.parse(result.text);
      final olEls = els.where((e) => e.kind == MdElKind.ol).toList();
      expect(olEls, hasLength(3));
      expect(olEls[0].indentLevel, 0);
      expect(olEls[0].seqNum, 1); // 'first' stays 1.
      expect(olEls[1].indentLevel, 1);
      // A newly nested depth anchors to ITS OWN first line's source digit
      // (GFM/CommonMark semantics, unrelated to Indent/Dedent) — Indent
      // never rewrites digits, only prepends whitespace, so the nested
      // block still literally says "2." and renders starting there.
      expect(olEls[1].seqNum, 2);
      expect(olEls[2].indentLevel, 0);
      expect(olEls[2].seqNum, 2); // 'third' continues the depth-0 sequence.
    });

    test(
        'dedenting a nested ol item merges it back into the parent '
        "sequence's count", () {
      const source = '1. first\n\t1. nested\n2. second';
      final nestedLineStart = source.indexOf('\t1. nested');
      final result = applyDedent(
        source,
        TextSelection.collapsed(offset: nestedLineStart + 3),
      );
      final els = MdParser.parse(result.text);
      final olEls = els.where((e) => e.kind == MdElKind.ol).toList();
      expect(olEls, hasLength(3));
      expect(olEls.every((e) => e.indentLevel == 0), isTrue);
      expect(olEls[0].seqNum, 1);
      expect(olEls[1].seqNum, 2);
      expect(olEls[2].seqNum, 3);
    });
  });

  // ===========================================================================
  // Widget-level coverage: toolbar/key equivalence and the full
  // type-'-'-Enter-Indent workflow.
  // ===========================================================================

  Widget buildEditor({
    required String initialValue,
    required MarkdownEditorController controller,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: MarkdownEditor(
                initialValue: initialValue,
                controller: controller,
              ),
            ),
            FormattingToolbar(controller: controller),
          ],
        ),
      ),
    );
  }

  group('Toolbar button / keystroke equivalence', () {
    testWidgets(
        'the Indent toolbar button and the Tab key produce identical '
        'results from the same starting state', (tester) async {
      final buttonController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '- item',
        controller: buttonController,
      ));
      buttonController
          .setSelectionForTesting(const TextSelection.collapsed(offset: 4));
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.indentIncrease));
      await tester.pump();
      // Capture before the next pumpWidget call replaces the tree and
      // detaches buttonController (currentValue/selectionForTesting fall
      // back to their "no editor attached" defaults once detached).
      final buttonValue = buttonController.currentValue;
      final buttonSelection = buttonController.selectionForTesting;

      // Force a full teardown before building the second tree: since the
      // next tree is structurally identical (same widget types at the same
      // positions, only a different controller instance), Flutter would
      // otherwise reuse the existing _MarkdownEditorState via
      // didUpdateWidget instead of disposing/re-initState-ing it — which
      // never re-attaches to the new controller (only initState/dispose
      // call MarkdownEditorController._attach/_detach), leaving
      // keyController permanently unattached.
      await tester.pumpWidget(const SizedBox());

      final keyController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '- item',
        controller: keyController,
      ));
      keyController
          .setSelectionForTesting(const TextSelection.collapsed(offset: 4));
      keyController.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(buttonValue, keyController.currentValue);
      expect(buttonValue, '\t- item');
      expect(buttonSelection, keyController.selectionForTesting);
    });

    testWidgets(
        'the Dedent toolbar button and Shift+Tab produce identical results '
        'from the same starting state', (tester) async {
      final buttonController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - item',
        controller: buttonController,
      ));
      buttonController
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.indentDecrease));
      await tester.pump();
      // Capture before the next pumpWidget call replaces the tree and
      // detaches buttonController.
      final buttonValue = buttonController.currentValue;
      final buttonSelection = buttonController.selectionForTesting;

      // Force a full teardown before building the second tree — see the
      // comment in the Indent-vs-Tab equivalence test above for why this is
      // necessary (structurally-identical trees otherwise reuse State via
      // didUpdateWidget, which never re-attaches to a new controller).
      await tester.pumpWidget(const SizedBox());

      final keyController = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '  - item',
        controller: keyController,
      ));
      keyController
          .setSelectionForTesting(const TextSelection.collapsed(offset: 8));
      keyController.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(buttonValue, keyController.currentValue);
      expect(buttonValue, '- item');
      expect(buttonSelection, keyController.selectionForTesting);
    });

    testWidgets('renders Indent and Dedent toolbar buttons', (tester) async {
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '',
        controller: controller,
      ));

      expect(find.byIcon(LucideIcons.indentIncrease), findsOneWidget);
      expect(find.byIcon(LucideIcons.indentDecrease), findsOneWidget);
    });
  });

  group('End-to-end: type "-", press Enter, press Indent', () {
    testWidgets(
        'the auto-continued (still empty) new line becomes nested after '
        'Indent', (tester) async {
      final controller = MarkdownEditorController();
      await tester.pumpWidget(buildEditor(
        initialValue: '',
        controller: controller,
      ));

      controller.requestFocus();
      await tester.pump();

      // Simulate IME typing "- item".
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();

      // Simulate Enter — list auto-continue inserts "- " on the new line.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '- item\n- ',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      await tester.pump();
      expect(controller.currentValue, '- item\n- ');

      // Press Indent on the new, still-empty list line.
      await tester.tap(find.byIcon(LucideIcons.indentIncrease));
      await tester.pump();

      expect(controller.currentValue, '- item\n\t- ');
      final els = MdParser.parse(controller.currentValue);
      final newLineEl = els.last;
      expect(newLineEl.kind, MdElKind.ul);
      expect(newLineEl.indentLevel, 1);
    });
  });
}
