import 'package:flutter/material.dart';

import 'block_splitter.dart';
import 'editor_config.dart';
import 'markdown_block.dart';

class MarkdownEditorController {
  _MarkdownEditorState? _state;
  TextEditingController? _activeTextController;

  void _attach(_MarkdownEditorState state) {
    _state = state;
    if (state._plainTextMode) _activeTextController = state._textController;
  }

  void _detach() {
    _state = null;
    _activeTextController = null;
  }

  void _setActiveTextController(TextEditingController? tc) {
    _activeTextController = tc;
  }

  String get currentValue => _state?.currentValue ?? '';
  void setValue(String value) => _state?.setValue(value);

  bool get plainTextMode => _state?._plainTextMode ?? false;
  void togglePlainTextMode() => _state?._togglePlainTextMode();

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

  void toggleUnorderedList() {
    final tc = _activeTextController;
    if (tc == null) return;
    final text = tc.text;
    final offset = tc.selection.baseOffset.clamp(0, text.length);
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
    _state?._notifyChanged(newText);
  }

  void toggleOrderedList() {
    final tc = _activeTextController;
    if (tc == null) return;
    final text = tc.text;
    final offset = tc.selection.baseOffset.clamp(0, text.length);
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
    _state?._notifyChanged(newText);
  }

  void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();
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
  // Plain-text mode fields (always initialised; active in plain-text mode only).
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  TextEditingValue _previousValue = TextEditingValue.empty;
  bool _suppressListener = false;

  // Block mode fields.
  late List<String> _blocks;
  bool _plainTextMode = false;
  int? _autofocusIndex;
  // Incremented on setValue() to force-recreate all MarkdownBlock widgets,
  // discarding any in-progress edit state when content is switched externally.
  int _resetCounter = 0;

  @override
  void initState() {
    super.initState();
    _blocks = BlockSplitter.split(widget.initialValue);
    _textController = TextEditingController(text: widget.initialValue);
    _previousValue = _textController.value;
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    widget.controller?._attach(this);
    _textController.addListener(_onTextChanged);

    if (widget.autofocus && !_plainTextMode && _blocks.isNotEmpty) {
      _autofocusIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _autofocusIndex = null);
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    widget.controller?._detach();
    _textController.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  String get currentValue =>
      _plainTextMode ? _textController.text : BlockSplitter.join(_blocks);

  void setValue(String value) {
    setState(() {
      _blocks = BlockSplitter.split(value);
      _autofocusIndex = null;
      _resetCounter++;
    });
    _suppressListener = true;
    _textController.value = TextEditingValue(text: value);
    _previousValue = _textController.value;
    _suppressListener = false;
    widget.controller?._setActiveTextController(null);
  }

  void _notifyChanged(String value) => widget.onChanged?.call(value);

  void _togglePlainTextMode() {
    if (_plainTextMode) {
      setState(() {
        _blocks = BlockSplitter.split(_textController.text);
        _plainTextMode = false;
      });
      widget.controller?._setActiveTextController(null);
    } else {
      final joined = BlockSplitter.join(_blocks);
      _suppressListener = true;
      _textController.value = TextEditingValue(text: joined);
      _previousValue = _textController.value;
      _suppressListener = false;
      setState(() => _plainTextMode = true);
      widget.controller?._setActiveTextController(_textController);
    }
  }

  void _onTextChanged() {
    if (_suppressListener) return;

    final current = _textController.value;
    final previous = _previousValue;
    _previousValue = current;

    if (current.text.length != previous.text.length + 1) return;
    final cursor = current.selection.baseOffset;
    if (cursor < 1) return;
    if (current.text[cursor - 1] != '\n') return;

    final insertPos = cursor - 1;
    final lineStart = current.text.lastIndexOf('\n', insertPos - 1) + 1;
    final completedLine = current.text.substring(lineStart, insertPos);

    final continuation = BlockSplitter.listContinuation(completedLine);
    if (continuation == null) return;

    final prefixLength = _listPrefixLength(completedLine);
    final content = completedLine.substring(prefixLength);
    if (content.isEmpty) {
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

  static int _listPrefixLength(String line) {
    final task = RegExp(r'^(- \[[ x]\] )').firstMatch(line);
    if (task != null) return task.group(1)!.length;
    final unordered = RegExp(r'^([-*] )').firstMatch(line);
    if (unordered != null) return unordered.group(1)!.length;
    final ordered = RegExp(r'^(\d+\. )').firstMatch(line);
    if (ordered != null) return ordered.group(1)!.length;
    return 0;
  }

  void _onBlockChanged(int i, String newContent) {
    _blocks[i] = newContent;
    widget.onChanged?.call(BlockSplitter.join(_blocks));
  }

  void _onEnterAtEnd(int i) {
    setState(() {
      _blocks.insert(i + 1, '');
      _autofocusIndex = i + 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _autofocusIndex = null);
    });
  }

  void _onMergeWithPrevious(int i) {
    if (i == 0) return;
    setState(() {
      _blocks[i - 1] = '${_blocks[i - 1]}\n${_blocks[i]}';
      _blocks.removeAt(i);
      _autofocusIndex = i - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _autofocusIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_plainTextMode) {
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

    return ListView.builder(
      itemCount: _blocks.length,
      itemBuilder: (context, i) {
        return MarkdownBlock(
          key: ValueKey('$_resetCounter-$i'),
          content: _blocks[i],
          config: widget.config,
          autofocus: i == _autofocusIndex,
          onChanged: (c) => _onBlockChanged(i, c),
          onFocused: widget.controller?._setActiveTextController,
          onUnfocused: () => widget.controller?._setActiveTextController(null),
          onEnterAtEnd: () => _onEnterAtEnd(i),
          onMergeWithPrevious: i == 0 ? null : () => _onMergeWithPrevious(i),
        );
      },
    );
  }
}
