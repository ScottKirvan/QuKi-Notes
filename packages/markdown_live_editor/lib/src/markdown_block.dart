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
    this.onSplit,
    this.autofocus = false,
  });

  final String content;
  final ValueChanged<String> onChanged;
  final MarkdownEditorConfig config;
  final ValueChanged<TextEditingController>? onFocused;
  final VoidCallback? onUnfocused;
  final VoidCallback? onMergeWithPrevious;
  final void Function(String before, String after)? onSplit;
  final bool autofocus;

  @override
  State<MarkdownBlock> createState() => _MarkdownBlockState();
}

class _MarkdownBlockState extends State<MarkdownBlock> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late bool _editing;
  bool _suppressListener = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content);
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
    if (widget.content != oldWidget.content) {
      _suppressListener = true;
      _textController.text = widget.content;
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

  // Detects newline insertion and splits the block. Normal edits propagate
  // through this listener so TextField.onChanged is not wired separately.
  void _onTextChanged() {
    if (_suppressListener) return;

    final text = _textController.text;
    final newlineIdx = text.indexOf('\n');

    if (newlineIdx == -1) {
      // Normal edit within the line.
      widget.onChanged(text);
      return;
    }

    // Newline detected — split this block into two.
    final before = text.substring(0, newlineIdx);
    final after = text.substring(newlineIdx + 1);

    final continuation = BlockSplitter.listContinuation(before);
    if (continuation != null) {
      final prefixLength = _listPrefixLength(before);
      if (before.substring(prefixLength).isEmpty) {
        // Empty list item → exit list (current line becomes empty).
        widget.onSplit?.call('', after);
        return;
      }
      widget.onSplit?.call(before, '$continuation$after');
      return;
    }

    widget.onSplit?.call(before, after);
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
        ),
      );
    }

    // Empty blocks (blank lines between paragraphs) need a minimum height so
    // they are visible and tappable. Non-empty blocks size to their content.
    final isEmpty = widget.content.isEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _enterEditMode,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: isEmpty ? 22 : 0),
        child: Padding(
          padding: widget.config.contentPadding,
          child: isEmpty
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
