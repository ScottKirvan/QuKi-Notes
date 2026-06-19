import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'block_splitter.dart';
import 'editor_config.dart';

class MarkdownBlock extends StatefulWidget {
  const MarkdownBlock({
    super.key,
    required this.content,
    required this.onChanged,
    required this.config,
    this.onFocused,
    this.onUnfocused,
    this.onMergeWithPrevious,
    this.onEnterAtEnd,
    this.autofocus = false,
  });

  final String content;
  final ValueChanged<String> onChanged;
  final MarkdownEditorConfig config;
  final ValueChanged<TextEditingController>? onFocused;
  final VoidCallback? onUnfocused;
  final VoidCallback? onMergeWithPrevious;
  final VoidCallback? onEnterAtEnd;
  final bool autofocus;

  @override
  State<MarkdownBlock> createState() => _MarkdownBlockState();
}

class _MarkdownBlockState extends State<MarkdownBlock> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late bool _editing;
  TextEditingValue _previousValue = TextEditingValue.empty;
  bool _suppressListener = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content);
    _previousValue = _textController.value;
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _textController.addListener(_onTextChanged);
    // Start in edit mode immediately when autofocused so the first frame shows
    // a TextField — avoids an invisible blank render view on new notes.
    _editing = widget.autofocus;
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
          widget.onFocused?.call(_textController);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MarkdownBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterEditMode();
      });
    }
    if (!_editing && widget.content != oldWidget.content) {
      _suppressListener = true;
      _textController.text = widget.content;
      _previousValue = _textController.value;
      _suppressListener = false;
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _editing) {
      setState(() => _editing = false);
      widget.onUnfocused?.call();
    }
  }

  void _enterEditMode() {
    if (_editing) return;
    setState(() => _editing = true);
    _focusNode.requestFocus();
    widget.onFocused?.call(_textController);
  }

  // List auto-continue: mirrors the plain-text mode logic in _MarkdownEditorState.
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
      // Empty list item → exit list.
      final newText = current.text.replaceRange(lineStart, insertPos + 1, '\n');
      _setValueSilently(newText, lineStart + 1);
      widget.onChanged(newText);
      return;
    }

    final newText = current.text.replaceRange(cursor, cursor, continuation);
    _setValueSilently(newText, cursor + continuation.length);
    widget.onChanged(newText);
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final sel = _textController.selection;
      if (sel.isCollapsed && sel.baseOffset == 0) {
        widget.onMergeWithPrevious?.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Focus(
        onKeyEvent: _handleKeyEvent,
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          // autofocus raises the soft keyboard on Android/iOS when the block
          // was created with autofocus: true.
          autofocus: widget.autofocus,
          maxLines: null,
          style: widget.config.textStyle,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding: widget.config.contentPadding,
          ),
          onChanged: widget.onChanged,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _enterEditMode,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: widget.config.contentPadding,
          child: widget.content.isEmpty
              ? const SizedBox.shrink()
              : MarkdownBody(
                  data: widget.content,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: widget.config.textStyle,
                  ),
                  softLineBreak: true,
                  checkboxBuilder: (bool checked) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
