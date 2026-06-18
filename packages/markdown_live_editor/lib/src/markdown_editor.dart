import 'package:flutter/material.dart';

import 'editor_config.dart';

class MarkdownEditorController {
  _MarkdownEditorState? _state;

  void _attach(_MarkdownEditorState state) => _state = state;
  void _detach() => _state = null;

  TextEditingController? get _activeTextController => _state?._textController;

  String get currentValue => _state?._textController.text ?? '';

  void setValue(String value) => _state?.setValue(value);

  // Stage 1/2: always plain-text; becomes functional in Stage 3.
  bool get plainTextMode => true;
  void togglePlainTextMode() {}

  /// Wraps the current selection with [prefix] and [suffix].
  /// If nothing is selected, inserts markers at the cursor position.
  void wrapSelection(String prefix, String suffix) {
    final tc = _activeTextController;
    if (tc == null) return;
    final sel = tc.selection;
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
    _state?._notifyChanged(newText);
  }

  /// Adds [prefix] to the current line if absent; removes it if present.
  void toggleLinePrefix(String prefix) {
    final tc = _activeTextController;
    if (tc == null) return;
    final text = tc.text;
    final offset = tc.selection.baseOffset.clamp(0, text.length);
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
    _state?._notifyChanged(newText);
  }

  void dismissKeyboard() => _state?._focusNode.unfocus();
}

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
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  TextEditingValue _previousValue = TextEditingValue.empty;
  bool _suppressListener = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue);
    _previousValue = _textController.value;
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    widget.controller?._attach(this);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    widget.controller?._detach();
    _textController.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void setValue(String value) {
    if (_textController.text != value) {
      _suppressListener = true;
      _textController.value = TextEditingValue(text: value);
      _previousValue = _textController.value;
      _suppressListener = false;
    }
  }

  void _notifyChanged(String value) => widget.onChanged?.call(value);

  void _onTextChanged() {
    if (_suppressListener) return;

    final current = _textController.value;
    final previous = _previousValue;
    _previousValue = current;

    // Only act on a single \n insertion (user pressed Enter).
    if (current.text.length != previous.text.length + 1) return;
    final cursor = current.selection.baseOffset;
    if (cursor < 1) return;
    if (current.text[cursor - 1] != '\n') return;

    // Locate the completed line (everything before the inserted \n).
    final insertPos = cursor - 1;
    final lineStart = current.text.lastIndexOf('\n', insertPos - 1) + 1;
    final completedLine = current.text.substring(lineStart, insertPos);

    final info = _listPrefixInfo(completedLine);
    if (info == null) return;

    final content = completedLine.substring(info.currentLength);
    if (content.isEmpty) {
      // Empty list item — exit the list by removing the prefix on this line.
      final newText = current.text.replaceRange(lineStart, insertPos + 1, '\n');
      _setValueSilently(newText, lineStart);
      return;
    }

    // Auto-continue: insert the continuation prefix on the new line.
    final newText =
        current.text.replaceRange(cursor, cursor, info.continuation);
    _setValueSilently(newText, cursor + info.continuation.length);
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

  static _ListPrefixResult? _listPrefixInfo(String line) {
    // Task list: - [ ] or - [x] — always continue with unchecked.
    final taskMatch = RegExp(r'^(- \[[ x]\] )').firstMatch(line);
    if (taskMatch != null) {
      return _ListPrefixResult(
        currentLength: taskMatch.group(1)!.length,
        continuation: '- [ ] ',
      );
    }
    // Unordered: - or *
    final unorderedMatch = RegExp(r'^([-*] )').firstMatch(line);
    if (unorderedMatch != null) {
      final prefix = unorderedMatch.group(1)!;
      return _ListPrefixResult(
          currentLength: prefix.length, continuation: prefix);
    }
    // Ordered: 1. 2. etc. — increment the number.
    final orderedMatch = RegExp(r'^(\d+)\. ').firstMatch(line);
    if (orderedMatch != null) {
      final numStr = orderedMatch.group(1)!;
      final num = int.parse(numStr);
      final currentLength = numStr.length + 2; // digits + ". "
      return _ListPrefixResult(
        currentLength: currentLength,
        continuation: '${num + 1}. ',
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _textController,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: widget.config.textStyle,
      decoration: InputDecoration(
        border: InputBorder.none,
        contentPadding: widget.config.contentPadding,
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _ListPrefixResult {
  const _ListPrefixResult(
      {required this.currentLength, required this.continuation});
  final int currentLength;
  final String continuation;
}
