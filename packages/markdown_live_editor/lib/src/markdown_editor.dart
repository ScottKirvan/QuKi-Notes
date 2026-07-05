import 'package:flutter/material.dart';

import 'editor_config.dart';
import 'quiki_editor.dart';
import 'span_parser.dart';

// ---------------------------------------------------------------------------
// Internal TextEditingController that renders markdown via buildTextSpan().
// ---------------------------------------------------------------------------

class _MarkdownTextController extends TextEditingController {
  _MarkdownTextController({super.text, required this.config});

  MarkdownEditorConfig config;
  bool styled = true;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!styled) {
      return TextSpan(text: text, style: style);
    }

    final effectiveStyle = style ?? const TextStyle();
    final baseColor = effectiveStyle.color ?? Colors.black;
    final syntaxColor = config.syntaxColor ?? baseColor.withValues(alpha: 0.35);

    final headingFontSize = (effectiveStyle.fontSize ?? 16) * 1.4;
    final headingStyle = effectiveStyle.copyWith(
      fontSize: headingFontSize,
      fontWeight: FontWeight.bold,
      color: baseColor,
    );
    final boldStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
    final italicStyle = effectiveStyle.copyWith(fontStyle: FontStyle.italic);
    final codeStyle = effectiveStyle.copyWith(fontFamily: 'monospace');
    final strikethroughStyle =
        effectiveStyle.copyWith(decoration: TextDecoration.lineThrough);
    final listPrefixStyle = effectiveStyle.copyWith(color: baseColor);
    final checkboxStyle = effectiveStyle.copyWith(
      fontFamily: 'monospace',
      color: baseColor,
    );

    final parser = MarkdownSpanParser(
      textStyle: effectiveStyle,
      syntaxColor: syntaxColor,
      headingStyle: headingStyle,
      boldStyle: boldStyle,
      italicStyle: italicStyle,
      codeStyle: codeStyle,
      strikethroughStyle: strikethroughStyle,
      listPrefixStyle: listPrefixStyle,
      checkboxStyle: checkboxStyle,
    );

    final fullText = text;
    if (fullText.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // Determine which line the cursor is on.
    final cursorOffset = selection.isValid ? selection.baseOffset : -1;
    final cursorLine = cursorOffset >= 0
        ? '\n'.allMatches(fullText.substring(0, cursorOffset)).length
        : -1;

    final lines = fullText.split('\n');
    final allSpans = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        allSpans.add(TextSpan(text: '\n', style: effectiveStyle));
      }
      final lineSpans =
          parser.parseLine(lines[i], isCursorLine: i == cursorLine);
      allSpans.addAll(lineSpans);
    }

    return TextSpan(children: allSpans, style: style);
  }
}

// ---------------------------------------------------------------------------
// Public controller — preserves the existing API exactly.
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

  String get currentValue => _state?._textController.text ?? '';

  void setValue(String value) => _state?._setValue(value);

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
        offset: sel.start + prefix.length + selected.length + suffix.length,
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
  });

  final String initialValue;
  final ValueChanged<String>? onChanged;
  final MarkdownEditorController? controller;
  final MarkdownEditorConfig config;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late _MarkdownTextController _textController;
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
    _textController = _MarkdownTextController(
      text: widget.initialValue,
      config: widget.config,
    );
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
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config != oldWidget.config) {
      _textController.config = widget.config;
    }
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

  static final _taskPrefixRe = RegExp(r'^(- \[[ x]\] )');
  static final _unorderedPrefixRe = RegExp(r'^([-*] )');
  static final _orderedRe = RegExp(r'^(\d+)\. ');

  static String? _listContinuation(String line) {
    if (_taskPrefixRe.hasMatch(line)) return '- [ ] ';
    final unordered = _unorderedPrefixRe.firstMatch(line);
    if (unordered != null) return unordered.group(1)!;
    final ordered = _orderedRe.firstMatch(line);
    if (ordered != null) {
      final n = int.parse(ordered.group(1)!);
      return '${n + 1}. ';
    }
    return null;
  }

  static int _listPrefixLength(String line) {
    final task = _taskPrefixRe.firstMatch(line);
    if (task != null) return task.group(1)!.length;
    final unordered = _unorderedPrefixRe.firstMatch(line);
    if (unordered != null) return unordered.group(1)!.length;
    final ordered = RegExp(r'^(\d+\. )').firstMatch(line);
    if (ordered != null) return ordered.group(1)!.length;
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

  void _togglePlainTextMode() {
    setState(() {
      _plainTextMode = !_plainTextMode;
      _textController.styled = !_plainTextMode;
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
    );
  }
}
