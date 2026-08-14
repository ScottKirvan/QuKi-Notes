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

// ---------------------------------------------------------------------------
// Shared list-marker detection — used by both the toggleUnorderedList /
// toggleOrderedList / toggleCheckboxList toolbar buttons below and the list
// auto-continue logic in _MarkdownEditorState._onTextChanged, so both stay
// consistent about what counts as "this line already has a list marker."
//
// Leading whitespace is always treated as belonging to the line, not the
// marker (matching MdParser._listIndent / MdParser's wsLen > 0 branch on the
// parsing/rendering side, ADR-34) — a marker is only recognized once any
// leading spaces/tabs have been skipped, so nested list items are detected
// the same way at any indentation depth.
// ---------------------------------------------------------------------------

final RegExp _leadingWsRe = RegExp(r'^([ \t]*)');
final RegExp _taskPrefixRe = RegExp(r'^(- \[[ xX]\] )');
final RegExp _unorderedPrefixRe = RegExp(r'^([-*] )');
final RegExp _orderedPrefixRe = RegExp(r'^\d+\. ');

String _leadingWs(String line) => _leadingWsRe.firstMatch(line)!.group(1)!;

enum _ListMarkerType { unordered, ordered, checkbox }

/// The marker text each type produces when adding a marker to a line with
/// none, or converting a line from a different type. Ordered always uses a
/// literal '1. ' — RenderModel computes block-relative sequential numbers at
/// display time (ADR-31 Stage 4), so the literal stored digit doesn't need
/// to be correct.
const Map<_ListMarkerType, String> _newListMarkerText = {
  _ListMarkerType.unordered: '- ',
  _ListMarkerType.ordered: '1. ',
  _ListMarkerType.checkbox: '- [ ] ',
};

/// An existing list marker found on a line: its type, the length of the
/// line's leading whitespace, and the length of the marker itself
/// (excluding that leading whitespace).
class _ListMarkerMatch {
  const _ListMarkerMatch(this.type, this.wsLen, this.markerLen);
  final _ListMarkerType type;
  final int wsLen;
  final int markerLen;
}

/// Detects whether [line] already carries one of the three list-marker types
/// immediately after its leading indentation. Checked in this priority order
/// — checkbox before unordered — because a checkbox marker ('- [ ] ') would
/// otherwise also match the plain unordered pattern ('- ') on its leading
/// "- ".
_ListMarkerMatch? _detectListMarker(String line) {
  final ws = _leadingWs(line);
  final rest = line.substring(ws.length);
  final task = _taskPrefixRe.firstMatch(rest);
  if (task != null) {
    return _ListMarkerMatch(_ListMarkerType.checkbox, ws.length, task.end);
  }
  final unordered = _unorderedPrefixRe.firstMatch(rest);
  if (unordered != null) {
    return _ListMarkerMatch(
        _ListMarkerType.unordered, ws.length, unordered.end);
  }
  final ordered = _orderedPrefixRe.firstMatch(rest);
  if (ordered != null) {
    return _ListMarkerMatch(_ListMarkerType.ordered, ws.length, ordered.end);
  }
  return null;
}

/// Line boundaries containing [offset]: `(lineStart, lineEnd)`, `lineEnd`
/// exclusive of the '\n' separator (or text.length for the last line).
(int, int) _lineBoundsAt(String text, int offset) {
  final lineStart = offset > 0 ? text.lastIndexOf('\n', offset - 1) + 1 : 0;
  final rawEnd = text.indexOf('\n', offset);
  final lineEnd = rawEnd == -1 ? text.length : rawEnd;
  return (lineStart, lineEnd);
}

/// The result of applying one list-toggle button's remove/convert/add
/// decision to a single line: the new line text, plus enough of the old
/// line's marker geometry ([wsLen], [oldMarkerLen], [newMarkerLen]) to
/// precisely remap an offset that fell anywhere in the old line into the new
/// line's coordinates. Shared by both the single-line/collapsed-selection
/// path ([_applyListMarkerToggle]) and the multi-line-selection path
/// ([_applyListMarkerToggleMultiLine]) below — the decision logic itself is
/// identical in both; only how many lines it's applied to differs.
class _LineToggleEdit {
  const _LineToggleEdit(
      this.newLine, this.wsLen, this.oldMarkerLen, this.newMarkerLen);
  final String newLine;
  final int wsLen;
  final int oldMarkerLen;
  final int newMarkerLen;
}

/// Applies [targetType]'s remove/convert/add decision to a single [line]:
///  - the line is a heading → left completely untouched (a zero-length,
///    no-op edit). These three buttons are list-marker buttons, not
///    general-purpose line-prefix buttons, and prepending a list marker
///    before a heading's leading '#' would silently stop it being
///    recognized as a heading — so a heading is never treated as a bare/
///    no-marker line to add a marker to, on either the collapsed-selection
///    path ([_applyListMarkerToggle]) or the multi-line path
///    ([_applyListMarkerToggleMultiLine]) that call this function. (The
///    multi-line path also independently filters heading lines out before
///    ever reaching this function — see its `eligibleLines` construction —
///    so this check is what actually does the work for the collapsed path,
///    and is simply never exercised by an already-filtered heading line
///    coming from the multi-line path.)
///  - the line already has a marker of [targetType] → remove it entirely,
///    leaving leading indentation and content unchanged.
///  - the line already has a marker of a different type → replace it with
///    [targetType]'s marker, preserving indentation and content.
///  - the line has no marker → insert [targetType]'s marker immediately
///    after any leading indentation.
_LineToggleEdit _toggleLine(String line, _ListMarkerType targetType) {
  if (_isHeadingLine(line)) {
    return _LineToggleEdit(line, 0, 0, 0);
  }
  final match = _detectListMarker(line);
  final wsLen = match?.wsLen ?? _leadingWs(line).length;
  final ws = line.substring(0, wsLen);
  final oldMarkerLen = match?.markerLen ?? 0;
  final content = line.substring(wsLen + oldMarkerLen);

  final removing = match?.type == targetType;
  final newMarker = removing ? '' : _newListMarkerText[targetType]!;
  final newLine = '$ws$newMarker$content';
  return _LineToggleEdit(newLine, wsLen, oldMarkerLen, newMarker.length);
}

/// Applies one list-toggle button's action to the single line containing
/// [selection]'s base offset — i.e. the collapsed-selection case. See
/// [_toggleLine] for the per-line remove/convert/add rule, including its
/// heading no-op case (a collapsed selection on a heading line leaves both
/// the text and the cursor position completely unchanged).
///
/// The resulting cursor offset shifts by the difference between the old and
/// new marker lengths (leading whitespace is never touched, so it never
/// contributes to the shift), then clamps to the edited line — the same
/// clamp-based convention toggleLinePrefix already uses. For a heading line
/// this shift is always 0, since [_toggleLine] reports zero-length old/new
/// markers for that case.
TextEditingValue _applyListMarkerToggle(
  String text,
  TextSelection selection,
  _ListMarkerType targetType,
) {
  final offset = selection.baseOffset.clamp(0, text.length);
  final (lineStart, lineEnd) = _lineBoundsAt(text, offset);
  final line = text.substring(lineStart, lineEnd);

  final edit = _toggleLine(line, targetType);
  final delta = edit.newMarkerLen - edit.oldMarkerLen;
  final newOffset =
      (offset + delta).clamp(lineStart, lineStart + edit.newLine.length);

  final newText = text.replaceRange(lineStart, lineEnd, edit.newLine);
  return TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newOffset),
  );
}

/// Applies [targetType]'s remove/convert/add decision independently to every
/// line touched by a genuine (non-collapsed) multi-line [selection] —
/// mirrors indent_dedent.dart's `_indentOrDedentSelection` technique:
/// enumerate every touched line, edit each one from last to first so earlier
/// lines' absolute offsets stay valid while later ones mutate, then remap the
/// selection's endpoints through the accumulated per-line splice deltas so
/// the result still spans the same logical content rather than collapsing to
/// a point.
///
/// Heading lines are excluded entirely — left untouched, never treated as a
/// bare/no-marker line to add a marker to. These three buttons are
/// list-marker buttons, not general-purpose line-prefix buttons, and
/// prepending a list marker before a heading's leading '#' would silently
/// stop it being recognized as a heading. This applies identically on the
/// single-line/collapsed-selection path above ([_applyListMarkerToggle]) —
/// [_toggleLine]'s own heading check is what makes that path a no-op for a
/// heading line, so it does not need a separate `eligibleLines`-style filter
/// the way this function does. The filter below is still needed here (rather
/// than relying solely on [_toggleLine]'s internal check) so a selection
/// touching ONLY heading lines can early-return as a whole-selection no-op
/// instead of doing a real no-op edit per line.
TextEditingValue _applyListMarkerToggleMultiLine(
  String text,
  TextSelection selection,
  _ListMarkerType targetType,
) {
  final start = selection.start;
  final end = selection.end;

  // A selection ending exactly at the start of a line does not "touch" that
  // line (mirrors indent_dedent.dart's _indentOrDedentSelection).
  final anchorEnd = end > start ? end - 1 : end;

  final lineStarts = <int>[];
  var pos = _lineBoundsAt(text, start).$1;
  while (true) {
    lineStarts.add(pos);
    final lineEnd = _lineBoundsAt(text, pos).$2;
    if (lineEnd >= anchorEnd || lineEnd >= text.length) break;
    pos = lineEnd + 1;
  }

  final eligibleLines = <int>[
    for (final ls in lineStarts)
      if (!_isHeadingLine(text.substring(ls, _lineBoundsAt(text, ls).$2))) ls,
  ];

  if (eligibleLines.isEmpty) {
    // Every touched line is a heading — nothing to do.
    return TextEditingValue(text: text, selection: selection);
  }

  // Compute each eligible line's edit against the ORIGINAL text before any
  // mutation, so the remap below stays correct regardless of the order lines
  // are actually mutated in.
  final edits = <int, _LineToggleEdit>{
    for (final ls in eligibleLines)
      ls: _toggleLine(
          text.substring(ls, _lineBoundsAt(text, ls).$2), targetType),
  };

  // Apply from last to first so earlier lines' offsets stay valid absolute
  // positions in the mutating text.
  var newText = text;
  for (final ls in eligibleLines.reversed) {
    final lineEnd = _lineBoundsAt(newText, ls).$2;
    newText = newText.replaceRange(ls, lineEnd, edits[ls]!.newLine);
  }

  // Remap one offset by walking every eligible line in ascending order and
  // accumulating each one's contribution: an offset strictly before that
  // line's marker is unaffected by it; an offset at/after the marker's old
  // end shifts by that line's full delta; an offset inside the old marker
  // itself clamps to the marker's (fixed) start position, matching the
  // single-line path's own clamp-to-boundary convention.
  int remap(int offset) {
    var shift = 0;
    for (final ls in eligibleLines) {
      final edit = edits[ls]!;
      final spliceStart = ls + edit.wsLen;
      final spliceOldEnd = spliceStart + edit.oldMarkerLen;
      if (offset <= spliceStart) {
        continue;
      } else if (offset >= spliceOldEnd) {
        shift += edit.newMarkerLen - edit.oldMarkerLen;
      } else {
        shift += spliceStart - offset;
      }
    }
    return offset + shift;
  }

  return TextEditingValue(
    text: newText,
    selection: TextSelection(
      baseOffset: remap(selection.baseOffset),
      extentOffset: remap(selection.extentOffset),
    ),
  );
}

/// True if [line] starts with a recognized heading prefix ('#' through
/// '######', each followed by a space) at column 0 — no leading whitespace.
/// Duplicated from indent_dedent.dart's own duplicate of MdParser's heading
/// check (Dart privacy is per-file); used to exclude heading lines from the
/// list-toggle buttons — both via [_toggleLine]'s own no-op check (the
/// collapsed-selection path) and via the eligibility filter in
/// [_applyListMarkerToggleMultiLine] (the multi-line path).
bool _isHeadingLine(String line) =>
    line.startsWith('# ') ||
    line.startsWith('## ') ||
    line.startsWith('### ') ||
    line.startsWith('#### ') ||
    line.startsWith('##### ') ||
    line.startsWith('###### ');

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

  void toggleUnorderedList() => _applyListToggle(_ListMarkerType.unordered);

  void toggleOrderedList() => _applyListToggle(_ListMarkerType.ordered);

  /// Toggles a checkbox ('- [ ] ') marker on the current line. Deliberately
  /// a dedicated method rather than routing through [toggleLinePrefix] (as
  /// it did previously) — toggleLinePrefix matches only an exact literal
  /// prefix, so it can't detect/convert-from unordered or ordered markers,
  /// and unifying it with the other two list-toggle buttons here would have
  /// changed the heading button's behavior too, since both shared that one
  /// generic method.
  void toggleCheckboxList() => _applyListToggle(_ListMarkerType.checkbox);

  void _applyListToggle(_ListMarkerType targetType) {
    final tc = _state?._textController;
    if (tc == null) return;
    final sel = _effectiveSelection;
    final result = sel.isCollapsed
        ? _applyListMarkerToggle(tc.text, sel, targetType)
        : _applyListMarkerToggleMultiLine(tc.text, sel, targetType);
    tc.value = result;
    _state?._focusNode.requestFocus();
    _state?.widget.onChanged?.call(result.text);
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

  // Leading-whitespace and marker-detection regexes/helpers are shared at
  // file scope (_leadingWs, _taskPrefixRe, _unorderedPrefixRe,
  // _orderedPrefixRe, _detectListMarker) with the toggleUnorderedList /
  // toggleOrderedList / toggleCheckboxList toolbar-button logic above, so
  // list auto-continue and the toolbar buttons agree on what counts as an
  // existing list marker.

  static String? _listContinuation(String line) {
    final ws = _leadingWs(line);
    final rest = line.substring(ws.length);
    if (_taskPrefixRe.hasMatch(rest)) return '$ws- [ ] ';
    final unordered = _unorderedPrefixRe.firstMatch(rest);
    if (unordered != null) return '$ws${unordered[0]!}';
    final ordered = RegExp(r'^(\d+)\. ').firstMatch(rest);
    if (ordered != null) {
      final n = int.parse(ordered.group(1)!);
      return '$ws${n + 1}. ';
    }
    return null;
  }

  static int _listPrefixLength(String line) {
    final match = _detectListMarker(line);
    if (match == null) return 0;
    return match.wsLen + match.markerLen;
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
