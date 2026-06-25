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
    this.onArrowDownAtEnd,
    this.onArrowUpAtStart,
    this.autofocus = false,
    this.autofocusAtEnd = false,
  });

  final String content;
  final ValueChanged<String> onChanged;
  final MarkdownEditorConfig config;
  final ValueChanged<TextEditingController>? onFocused;
  final VoidCallback? onUnfocused;
  final VoidCallback? onMergeWithPrevious;
  final void Function(String before, String after)? onSplit;
  final VoidCallback? onArrowDownAtEnd;
  final VoidCallback? onArrowUpAtStart;
  final bool autofocus;
  // When true, the cursor is placed at the end of the content on focus
  // (used when navigating up from a block below).
  final bool autofocusAtEnd;

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
          if (widget.autofocusAtEnd) {
            _textController.selection = TextSelection.collapsed(
              offset: _textController.text.length,
            );
          }
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
        if (mounted) {
          _enterEditMode();
          if (widget.autofocusAtEnd) {
            // _enterEditMode() schedules a rebuild; wait one more frame for the
            // TextField to be present before setting the selection.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _textController.selection = TextSelection.collapsed(
                  offset: _textController.text.length,
                );
              }
            });
          }
        }
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

    // Reset immediately so that Android IME re-fires of the same change do not
    // trigger a second split.
    _suppressListener = true;
    _textController.value = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    _suppressListener = false;

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

  // Each block is one physical line, so there is at most one checkbox per
  // block. replaceFirst is sufficient — no index counter needed.
  void _toggleCheckbox(bool wasChecked) {
    final newContent = wasChecked
        ? widget.content.replaceFirst(RegExp(r'- \[[xX]\] '), '- [ ] ')
        : widget.content.replaceFirst('- [ ] ', '- [x] ');
    widget.onChanged(newContent);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final sel = _textController.selection;

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (sel.isCollapsed && sel.baseOffset == 0) {
        widget.onMergeWithPrevious?.call();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (sel.isCollapsed && sel.baseOffset == 0) {
        widget.onArrowUpAtStart?.call();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (sel.isCollapsed && sel.baseOffset == _textController.text.length) {
        widget.onArrowDownAtEnd?.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Empty blocks (blank lines between paragraphs) need a minimum height so
    // they are visible and tappable. Non-empty blocks size to their content.
    //
    // A line containing only a list/heading marker with no following text
    // (e.g. "- ", "# ") causes flutter_markdown to assert
    // '_inlines.isEmpty': is not true because the parser produces a block
    // element with zero inline children.  Appending a zero-width space (​)
    // gives the parser one inline to work with while remaining visually
    // invisible, so the bullet/heading renders normally.
    //
    // Bare task items (e.g. "- [ ] ") hit the same assertion via a different
    // path: the checkbox WidgetSpan is added to _inlines but has no inline
    // sibling, so the builder asserts on close.  The zero-width-space trick
    // does not fix this case.  Instead, render bare task items directly as
    // Flutter widgets, bypassing MarkdownBody entirely (#138).
    final trimmed = widget.content.trimRight();
    final isBareMarker = trimmed.isNotEmpty &&
        RegExp(r'^(- \[[ x]\]|[-*]|#{1,6}|\d+\.)$').hasMatch(trimmed);
    final isBareTask =
        isBareMarker && RegExp(r'^- \[[ xX]\]$').hasMatch(trimmed);
    final isEmpty = widget.content.isEmpty;

    Widget renderBody;
    if (isEmpty) {
      renderBody = const SizedBox.shrink();
    } else if (isBareTask) {
      final checked = trimmed.contains('[x]') || trimmed.contains('[X]');
      renderBody = Row(
        children: [
          GestureDetector(
            onTap: () => _toggleCheckbox(checked),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Transform.translate(
                offset: const Offset(0, 5),
                child: Icon(
                  checked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      renderBody = MarkdownBody(
        data: isBareMarker ? '${widget.content}​' : widget.content,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: widget.config.textStyle,
          blockSpacing: 0,
          listBulletPadding: EdgeInsets.zero,
        ),
        softLineBreak: true,
        checkboxBuilder: (bool checked) => GestureDetector(
          onTap: () => _toggleCheckbox(checked),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Transform.translate(
              offset: const Offset(0, 5),
              child: Icon(
                checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
              ),
            ),
          ),
        ),
      );
    }

    final renderChild = GestureDetector(
      key: const ValueKey('render'),
      behavior: HitTestBehavior.opaque,
      onTap: _enterEditMode,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: isEmpty ? 22 : 0),
        child: Padding(
          padding: widget.config.contentPadding,
          child: renderBody,
        ),
      ),
    );

    final editChild = Focus(
      key: const ValueKey('edit'),
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
          isDense: true,
          contentPadding: widget.config.contentPadding,
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      // Default layoutBuilder uses Alignment.center; override to top-start so
      // blocks stay left-aligned during the crossfade.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: _editing ? editChild : renderChild,
    );
  }
}
