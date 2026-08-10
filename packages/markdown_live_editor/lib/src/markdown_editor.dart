import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'editor_config.dart';
import 'indent_dedent.dart';
import 'quiki_editor.dart';

// ---------------------------------------------------------------------------
// Public controller — preserves the existing API exactly.
//
// Rendering is done entirely by QuikiRenderEditor from the MdParser/RenderModel
// pipeline; the plain TextEditingController below is used only as the shared
// source-of-truth text buffer. (The former _MarkdownTextController.buildTextSpan
// override and its MarkdownSpanParser were dead code — QuikiRenderEditor never
// calls buildTextSpan — and were removed with ADR-33.)
// ---------------------------------------------------------------------------

class MarkdownEditorController {
  _MarkdownEditorState? _state;

  void _attach(_MarkdownEditorState state) => _state = state;
  void _detach() => _state = null;

  /// Whether the editor FocusNode currently has focus.
  ///
  /// Semantically equivalent to the old "a block is in edit mode" for
  /// FormattingToolbar enable/disable purposes.
  bool get hasActiveBlock => _state?._focusNode.hasFocus ?? false;

  /// Called each time the editor's FocusNode gains or loses focus.
  ///
  /// Set in the host widget's [initState] so host UI (toolbar visibility,
  /// AppBar icons) rebuilds on keyboard show/hide without polling.
  VoidCallback? onFocusChanged;

  void unfocus() => _state?._focusNode.unfocus();

  String get currentValue => _state?._textController.text ?? '';

  void setValue(String value) => _state?._setValue(value);

  /// Replaces the editor's text without disturbing the current selection or
  /// requesting focus — for an external content edit (e.g. a checkbox
  /// toggle, #335 / #266) that must not implicitly switch the note between
  /// reading and edit mode. Contrast with [setValue], which resets the
  /// selection to the top on purpose for a document switch (opening a
  /// different QuKi, or starting a new one) — that reset is correct there
  /// but was, before this method existed, also being applied to in-place
  /// edits it was never meant for, jumping the cursor to offset 0 (and, if
  /// offset 0 happened to fall inside a markdown element, revealing that
  /// line as raw source) as a side effect of a same-document edit.
  ///
  /// The selection is clamped to the new text's length so a same-length edit
  /// (the checkbox marker swap is always 6-for-6 chars) is a pure no-op on
  /// the selection, while a length-changing edit still leaves it valid.
  void setValuePreservingSelection(String value) =>
      _state?._setValuePreservingSelection(value);

  bool get plainTextMode => _state?._plainTextMode ?? false;
  void togglePlainTextMode() => _state?._togglePlainTextMode();

  void requestFocus() => _state?._focusNode.requestFocus();

  /// Alias for [requestFocus] — kept for API stability.
  void focusFirstBlock() => _state?._focusNode.requestFocus();

  /// Sets the current selection on the underlying text controller.
  ///
  /// Intended for widget tests that need to position the cursor or establish a
  /// selection before invoking toolbar operations.
  @visibleForTesting
  void setSelectionForTesting(TextSelection selection) {
    final tc = _state?._textController;
    if (tc == null) return;
    tc.value = tc.value.copyWith(selection: selection);
  }

  /// Returns the current editor selection. Intended for widget tests only.
  @visibleForTesting
  TextSelection get selectionForTesting {
    final tc = _state?._textController;
    return tc?.selection ?? const TextSelection.collapsed(offset: 0);
  }

  /// Returns the current selection if valid; otherwise returns the last saved
  /// valid selection. Toolbar methods call this so they can operate even after
  /// the TextField loses focus (which invalidates [TextEditingController.selection]
  /// before [onPressed] fires).
  TextSelection get _effectiveSelection {
    final tc = _state?._textController;
    if (tc == null) return const TextSelection.collapsed(offset: 0);
    return tc.selection.isValid ? tc.selection : (_state!._savedSelection);
  }

  void wrapSelection(String prefix, String suffix) {
    final tc = _state?._textController;
    if (tc == null) return;
    final sel = _effectiveSelection;
    if (!sel.isValid) return;
    final text = tc.text;
    final selected = sel.textInside(text);
    final newText =
        text.replaceRange(sel.start, sel.end, '$prefix$selected$suffix');
    tc.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // When no text was selected, place cursor between delimiters so the
        // user can type immediately. When text was wrapped, cursor goes after
        // the closing delimiter (standard wrap behaviour).
        offset: sel.start +
            prefix.length +
            (selected.isEmpty ? 0 : selected.length + suffix.length),
      ),
    );
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(newText);
  }

  void toggleLinePrefix(String prefix) {
    final tc = _state?._textController;
    if (tc == null) return;
    final text = tc.text;
    final offset = _effectiveSelection.baseOffset.clamp(0, text.length);
    final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
    final rawEnd = text.indexOf('\n', offset);
    final lineEnd = rawEnd == -1 ? text.length : rawEnd;
    final line = text.substring(lineStart, lineEnd);
    final String newLine;
    final int newOffset;
    if (line.startsWith(prefix)) {
      newLine = line.substring(prefix.length);
      newOffset =
          (offset - prefix.length).clamp(lineStart, lineStart + newLine.length);
    } else {
      newLine = '$prefix$line';
      newOffset = offset + prefix.length;
    }
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    tc.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(newText);
  }

  void toggleUnorderedList() {
    final tc = _state?._textController;
    if (tc == null) return;
    final text = tc.text;
    final offset = _effectiveSelection.baseOffset.clamp(0, text.length);
    final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
    final rawEnd = text.indexOf('\n', offset);
    final lineEnd = rawEnd == -1 ? text.length : rawEnd;
    final line = text.substring(lineStart, lineEnd);
    final existingMatch = RegExp(r'^(- \[[ x]\] |[-*] )').firstMatch(line);
    final String newLine;
    final int newOffset;
    if (existingMatch != null) {
      final prefixLen = existingMatch.group(1)!.length;
      newLine = line.substring(prefixLen);
      newOffset =
          (offset - prefixLen).clamp(lineStart, lineStart + newLine.length);
    } else {
      newLine = '- $line';
      newOffset = offset + 2;
    }
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    tc.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(newText);
  }

  void toggleOrderedList() {
    final tc = _state?._textController;
    if (tc == null) return;
    final text = tc.text;
    final offset = _effectiveSelection.baseOffset.clamp(0, text.length);
    final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
    final rawEnd = text.indexOf('\n', offset);
    final lineEnd = rawEnd == -1 ? text.length : rawEnd;
    final line = text.substring(lineStart, lineEnd);
    final orderedMatch = RegExp(r'^(\d+\. )').firstMatch(line);
    final String newLine;
    final int newOffset;
    if (orderedMatch != null) {
      final prefixLen = orderedMatch.group(1)!.length;
      newLine = line.substring(prefixLen);
      newOffset =
          (offset - prefixLen).clamp(lineStart, lineStart + newLine.length);
    } else {
      newLine = '1. $line';
      newOffset = offset + 3;
    }
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    tc.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(newText);
  }

  /// Increases indentation for the line(s) touched by the current selection
  /// (ADR-34 Stage 4 / #77). See indent_dedent.dart for the full per-line-
  /// kind rule set. Shares its implementation with the Tab key
  /// (QuikiEditorState._applyIndent) via [applyIndent] so the toolbar button
  /// and the keystroke are guaranteed to produce identical results.
  void indent() {
    final tc = _state?._textController;
    if (tc == null) return;
    final result = applyIndent(tc.text, _effectiveSelection);
    tc.value = TextEditingValue(text: result.text, selection: result.selection);
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(result.text);
  }

  /// Decreases indentation for the line(s) touched by the current selection
  /// (ADR-34 Stage 4 / #77). See [indent] and indent_dedent.dart.
  void dedent() {
    final tc = _state?._textController;
    if (tc == null) return;
    final result = applyDedent(tc.text, _effectiveSelection);
    tc.value = TextEditingValue(text: result.text, selection: result.selection);
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(result.text);
  }
}

// ---------------------------------------------------------------------------
// MarkdownEditor widget — public API preserved exactly.
// ---------------------------------------------------------------------------

class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.initialValue,
    this.onChanged,
    this.controller,
    this.config = const MarkdownEditorConfig(),
    this.focusNode,
    this.autofocus = false,
    this.imageLoader,
    this.onLinkTap,
    this.onCheckboxToggle,
  });

  final String initialValue;
  final ValueChanged<String>? onChanged;
  final MarkdownEditorController? controller;
  final MarkdownEditorConfig config;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Optional callback to resolve image paths to raw bytes.
  ///
  /// Receives the raw path string from the markdown source (e.g.
  /// `../images/photo.jpg`).  Return [Uint8List] bytes on success, or null
  /// if the path cannot be resolved or an error occurs.  The package never
  /// imports `dart:io` or any storage package — all file access is delegated
  /// through this callback.
  ///
  /// If null, or if the callback returns null, a gray placeholder rect is
  /// painted in place of the image.
  final Future<Uint8List?> Function(String path)? imageLoader;

  /// Called when the user taps a collapsed inline link.  Receives the raw URL
  /// string from the markdown source.  If null, tapping a collapsed link is a
  /// no-op (cursor does not move either).
  final void Function(String url)? onLinkTap;

  /// Called when the user taps a collapsed checkbox glyph (☐ or ☑).
  /// Receives the source offset of the checkbox element's start so the caller
  /// can swap the 6-char marker ('- [ ] ' ↔ '- [x] ') and trigger auto-save.
  /// If null, tapping a collapsed checkbox is a no-op (cursor does not move).
  final void Function(int sourceOffset)? onCheckboxToggle;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late TextEditingController _textController;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  bool _plainTextMode = false;
  bool _suppressListener = false;
  TextEditingValue _previousValue = TextEditingValue.empty;

  /// Last valid selection captured before focus leaves the TextField.
  /// Toolbar methods read this when [_textController.selection] is invalid.
  TextSelection _savedSelection = const TextSelection.collapsed(offset: 0);

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue);
    _previousValue = _textController.value;
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    widget.controller?._attach(this);

    // Rebuild on focus change so cursor-line highlighting updates when the
    // editor gains or loses focus (cursor line ↔ rendered mode).
    _focusNode.addListener(_onFocusChanged);
    _textController.addListener(_onTextChanged);
    _textController.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _textController.removeListener(_onTextChanged);
    _textController.removeListener(_onSelectionChanged);
    widget.controller?._detach();
    _textController.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // Trigger a rebuild so buildTextSpan() re-evaluates cursor-line status.
    if (mounted) setState(() {});
    widget.controller?.onFocusChanged?.call();
  }

  /// Saves the last valid selection so toolbar methods can use it after focus
  /// is lost (Flutter invalidates the selection before onPressed fires).
  void _onSelectionChanged() {
    if (_textController.selection.isValid) {
      _savedSelection = _textController.selection;
    }
  }

  // List auto-continue: when the user presses Enter after a list item, insert
  // the next list prefix automatically. Mirrors the old plain-text mode behavior.
  void _onTextChanged() {
    if (_suppressListener) return;

    final current = _textController.value;
    final previous = _previousValue;
    _previousValue = current;

    // Only act on single-character insertions of '\n'.
    if (current.text.length != previous.text.length + 1) return;
    final cursor = current.selection.baseOffset;
    if (cursor < 1) return;
    if (current.text[cursor - 1] != '\n') return;

    final insertPos = cursor - 1;
    final lineStart = current.text.lastIndexOf('\n', insertPos - 1) + 1;
    final completedLine = current.text.substring(lineStart, insertPos);

    final continuation = _listContinuation(completedLine);
    if (continuation == null) return;

    final prefixLength = _listPrefixLength(completedLine);
    final content = completedLine.substring(prefixLength);
    if (content.isEmpty) {
      // Empty list item → exit list (remove prefix from current line).
      final newText = current.text.replaceRange(lineStart, insertPos + 1, '\n');
      _setValueSilently(newText, lineStart);
      return;
    }

    final newText = current.text.replaceRange(cursor, cursor, continuation);
    _setValueSilently(newText, cursor + continuation.length);
    widget.onChanged?.call(newText);
  }

  void _setValueSilently(String text, int cursorOffset) {
    _suppressListener = true;
    _textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
    _previousValue = _textController.value;
    _suppressListener = false;
  }

  static final _leadingWsRe = RegExp(r'^([ \t]*)');
  static final _taskPrefixRe = RegExp(r'^(- \[[ x]\] )');
  static final _unorderedPrefixRe = RegExp(r'^([-*] )');
  static final _orderedRe = RegExp(r'^(\d+)\. ');

  /// The literal leading-whitespace prefix of [line] (spaces/tabs only).
  ///
  /// Used so list auto-continue preserves a nested item's own indentation
  /// (ADR-34 Stage 2+3) — the marker-matching regexes below run against the
  /// remainder *after* this prefix, and the prefix is then re-prepended to
  /// whatever continuation marker they produce, so continuing a `  - ` item
  /// inserts `  - ` again, not `- ` reset to the left margin.
  static String _leadingWs(String line) =>
      _leadingWsRe.firstMatch(line)!.group(1)!;

  static String? _listContinuation(String line) {
    final ws = _leadingWs(line);
    final rest = line.substring(ws.length);
    if (_taskPrefixRe.hasMatch(rest)) return '$ws- [ ] ';
    final unordered = _unorderedPrefixRe.firstMatch(rest);
    if (unordered != null) return '$ws${unordered.group(1)!}';
    final ordered = _orderedRe.firstMatch(rest);
    if (ordered != null) {
      final n = int.parse(ordered.group(1)!);
      return '$ws${n + 1}. ';
    }
    return null;
  }

  static int _listPrefixLength(String line) {
    final ws = _leadingWs(line);
    final rest = line.substring(ws.length);
    final task = _taskPrefixRe.firstMatch(rest);
    if (task != null) return ws.length + task.group(1)!.length;
    final unordered = _unorderedPrefixRe.firstMatch(rest);
    if (unordered != null) return ws.length + unordered.group(1)!.length;
    final ordered = RegExp(r'^(\d+\. )').firstMatch(rest);
    if (ordered != null) return ws.length + ordered.group(1)!.length;
    return 0;
  }

  void _setValue(String value) {
    _suppressListener = true;
    _textController.value = TextEditingValue(
      text: value,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _previousValue = _textController.value;
    _suppressListener = false;
  }

  /// See [MarkdownEditorController.setValuePreservingSelection].
  void _setValuePreservingSelection(String value) {
    _suppressListener = true;
    final current = _textController.selection;
    final preserved = current.isValid
        ? TextSelection(
            baseOffset: current.baseOffset.clamp(0, value.length),
            extentOffset: current.extentOffset.clamp(0, value.length),
          )
        : current;
    _textController.value = TextEditingValue(text: value, selection: preserved);
    _previousValue = _textController.value;
    _suppressListener = false;
  }

  void _togglePlainTextMode() {
    setState(() {
      _plainTextMode = !_plainTextMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return QuikiEditor(
      controller: _textController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      config: widget.config,
      onChanged: widget.onChanged,
      plainTextMode: _plainTextMode,
      imageLoader: widget.imageLoader,
      onLinkTap: widget.onLinkTap,
      onCheckboxToggle: widget.onCheckboxToggle,
    );
  }
}
