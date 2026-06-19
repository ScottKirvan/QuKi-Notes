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

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.content);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    // Start in edit mode immediately when autofocused so the TextField is
    // visible on the very first frame — avoids an invisible blank render view.
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
      _textController.text = widget.content;
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

  bool _isListBlock(String text) {
    final firstLine =
        text.contains('\n') ? text.substring(0, text.indexOf('\n')) : text;
    return BlockSplitter.listContinuation(firstLine) != null;
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

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final text = _textController.text;
      final offset = _textController.selection.baseOffset;
      if (offset == text.length && !_isListBlock(text)) {
        widget.onEnterAtEnd?.call();
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
                ),
        ),
      ),
    );
  }
}
