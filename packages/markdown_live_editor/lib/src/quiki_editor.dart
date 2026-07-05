import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_config.dart';
import 'quiki_render_editor.dart';

// ---------------------------------------------------------------------------
// _QuikiEditor — stateful widget
//
// Single responsibility: input and IME. Owns the TextInputConnection, scroll
// state, keyboard event handling, and tap-to-cursor mapping. Rendering is
// entirely delegated to QuikiRenderWidget / QuikiRenderEditor.
// ---------------------------------------------------------------------------

class QuikiEditor extends StatefulWidget {
  const QuikiEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.config,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final MarkdownEditorConfig config;
  final ValueChanged<String>? onChanged;

  @override
  QuikiEditorState createState() => QuikiEditorState();
}

class QuikiEditorState extends State<QuikiEditor> implements TextInputClient {
  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;
  final ScrollController _scrollController = ScrollController();

  // The render object — accessed for position-to-offset mapping and caret
  // scroll tracking.
  QuikiRenderEditor? get _renderEditor {
    final ctx = _renderKey.currentContext;
    if (ctx == null) return null;
    return ctx.findRenderObject() as QuikiRenderEditor?;
  }

  final GlobalKey _renderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _value = widget.controller.value;
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onFocusChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(QuikiEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _value = widget.controller.value;
      widget.controller.addListener(_onControllerChanged);
      _connection?.setEditingState(_value);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _connection?.close();
    _scrollController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Controller → IME sync
  // -------------------------------------------------------------------------

  void _onControllerChanged() {
    final newValue = widget.controller.value;
    if (newValue == _value) return;
    _value = newValue;
    _connection?.setEditingState(_value);
    if (mounted) setState(() {});
    _scheduleScrollToCaret();
  }

  // -------------------------------------------------------------------------
  // Focus handling — opens/closes the IME connection.
  // -------------------------------------------------------------------------

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _openConnection();
    } else {
      _closeConnection();
    }
    if (mounted) setState(() {});
  }

  void _openConnection() {
    if (_connection != null && _connection!.attached) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
    _connection!.show();
    _connection!.setEditingState(_value);
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
  }

  // -------------------------------------------------------------------------
  // TextInputClient interface
  // -------------------------------------------------------------------------

  @override
  TextEditingValue? get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value == _value) return;
    _updateValue(value, notify: true);
  }

  @override
  void performAction(TextInputAction action) {
    // newline is handled at the IME level for multiline; nothing to do here.
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {}

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  bool onFocusReceived() => false;

  @override
  void showToolbar() {}

  // -------------------------------------------------------------------------
  // Internal value update — keeps _value, controller, and IME in sync.
  // -------------------------------------------------------------------------

  void _updateValue(TextEditingValue value, {required bool notify}) {
    // Suppress the controller listener while we update to avoid a feedback loop.
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.value = value;
    // After setting the value, listeners on _MarkdownEditorState (e.g. list
    // auto-continue) may have fired synchronously and mutated the controller
    // further. Always read back the final controller value so _value and the
    // rendered state stay in sync with whatever the MarkdownEditor state machine
    // decided the canonical value should be.
    _value = widget.controller.value;
    widget.controller.addListener(_onControllerChanged);
    if (notify) {
      widget.onChanged?.call(_value.text);
    }
    if (mounted) setState(() {});
    _scheduleScrollToCaret();
  }

  // -------------------------------------------------------------------------
  // Scroll-to-caret: keeps the caret visible after each edit.
  // -------------------------------------------------------------------------

  void _scheduleScrollToCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final re = _renderEditor;
      if (re == null) return;
      if (!_scrollController.hasClients) return;
      final sel = _value.selection;
      if (!sel.isValid || !sel.isCollapsed) return;
      // Caret Y in text-painter space (no padding).
      final caretOffsetInText =
          re.getOffsetForCaret(TextPosition(offset: sel.baseOffset));
      // Add padding.top to get the Y position within the render object's local
      // coordinate space, which matches the SingleChildScrollView's content.
      final caretY = caretOffsetInText.dy + re.localPadding.top;
      final caretHeight = re.preferredLineHeight;
      final viewportHeight = _scrollController.position.viewportDimension;
      final currentScroll = _scrollController.offset;
      if (caretY < currentScroll) {
        _scrollController.jumpTo(caretY);
      } else if (caretY + caretHeight > currentScroll + viewportHeight) {
        _scrollController.jumpTo(caretY + caretHeight - viewportHeight);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Keyboard event handling
  // -------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (ctrl) {
      if (key == LogicalKeyboardKey.keyA) {
        _selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _cutSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteFromClipboard();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.backspace) {
      _handleBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _handleDelete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveLeft(extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveRight(extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveUp(extend: shift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveDown(extend: shift);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // -------------------------------------------------------------------------
  // Cursor movement helpers
  // -------------------------------------------------------------------------

  TextSelection get _sel => _value.selection;
  String get _text => _value.text;

  void _selectAll() {
    _updateValue(
      _value.copyWith(
        selection: TextSelection(baseOffset: 0, extentOffset: _text.length),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _copySelection() {
    if (_sel.isCollapsed) return;
    Clipboard.setData(ClipboardData(text: _sel.textInside(_text)));
  }

  void _cutSelection() {
    if (_sel.isCollapsed) return;
    Clipboard.setData(ClipboardData(text: _sel.textInside(_text)));
    _deleteSelection();
  }

  void _pasteFromClipboard() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text == null || !mounted) return;
      final text = data!.text!;
      final newText = _text.replaceRange(_sel.start, _sel.end, text);
      final newOffset = _sel.start + text.length;
      _updateValue(
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newOffset),
        ),
        notify: true,
      );
      _connection?.setEditingState(_value);
    });
  }

  void _handleBackspace() {
    if (!_sel.isValid) return;
    if (!_sel.isCollapsed) {
      _deleteSelection();
      return;
    }
    final offset = _sel.baseOffset;
    if (offset <= 0) return;
    final newText = _text.replaceRange(offset - 1, offset, '');
    _updateValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset - 1),
      ),
      notify: true,
    );
    _connection?.setEditingState(_value);
  }

  void _handleDelete() {
    if (!_sel.isValid) return;
    if (!_sel.isCollapsed) {
      _deleteSelection();
      return;
    }
    final offset = _sel.baseOffset;
    if (offset >= _text.length) return;
    final newText = _text.replaceRange(offset, offset + 1, '');
    _updateValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset),
      ),
      notify: true,
    );
    _connection?.setEditingState(_value);
  }

  void _deleteSelection() {
    if (_sel.isCollapsed) return;
    final newText = _text.replaceRange(_sel.start, _sel.end, '');
    _updateValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: _sel.start),
      ),
      notify: true,
    );
    _connection?.setEditingState(_value);
  }

  void _moveLeft({required bool extend}) {
    if (!_sel.isValid) return;
    if (!_sel.isCollapsed && !extend) {
      _updateValue(
        _value.copyWith(selection: TextSelection.collapsed(offset: _sel.start)),
        notify: false,
      );
    } else {
      final newOffset = (_sel.extentOffset - 1).clamp(0, _text.length);
      final newSel = extend
          ? _sel.copyWith(extentOffset: newOffset)
          : TextSelection.collapsed(offset: newOffset);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    }
    _connection?.setEditingState(_value);
  }

  void _moveRight({required bool extend}) {
    if (!_sel.isValid) return;
    if (!_sel.isCollapsed && !extend) {
      _updateValue(
        _value.copyWith(selection: TextSelection.collapsed(offset: _sel.end)),
        notify: false,
      );
    } else {
      final newOffset = (_sel.extentOffset + 1).clamp(0, _text.length);
      final newSel = extend
          ? _sel.copyWith(extentOffset: newOffset)
          : TextSelection.collapsed(offset: newOffset);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    }
    _connection?.setEditingState(_value);
  }

  void _moveUp({required bool extend}) {
    final re = _renderEditor;
    if (re == null || !_sel.isValid) return;
    final currentOffset = _sel.extentOffset;
    final currentXY = re.getOffsetForCaret(TextPosition(offset: currentOffset));
    final targetY = currentXY.dy - re.preferredLineHeight;
    if (targetY < 0) {
      final newSel = extend
          ? _sel.copyWith(extentOffset: 0)
          : const TextSelection.collapsed(offset: 0);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    } else {
      final newPos = re.getPositionForOffset(Offset(currentXY.dx, targetY));
      final newSel = extend
          ? _sel.copyWith(extentOffset: newPos.offset)
          : TextSelection.collapsed(offset: newPos.offset);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    }
    _connection?.setEditingState(_value);
  }

  void _moveDown({required bool extend}) {
    final re = _renderEditor;
    if (re == null || !_sel.isValid) return;
    final currentOffset = _sel.extentOffset;
    final currentXY = re.getOffsetForCaret(TextPosition(offset: currentOffset));
    final targetY = currentXY.dy + re.preferredLineHeight;
    final maxY = re.textHeight - 1;
    if (targetY > maxY) {
      final newSel = extend
          ? _sel.copyWith(extentOffset: _text.length)
          : TextSelection.collapsed(offset: _text.length);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    } else {
      final newPos = re.getPositionForOffset(Offset(currentXY.dx, targetY));
      final newSel = extend
          ? _sel.copyWith(extentOffset: newPos.offset)
          : TextSelection.collapsed(offset: newPos.offset);
      _updateValue(_value.copyWith(selection: newSel), notify: false);
    }
    _connection?.setEditingState(_value);
  }

  // -------------------------------------------------------------------------
  // Tap handling
  // -------------------------------------------------------------------------

  void _onTapDown(TapDownDetails details) {
    // Ensure the widget has focus so the keyboard opens.
    if (!widget.focusNode.hasFocus) {
      widget.focusNode.requestFocus();
    }
    final re = _renderEditor;
    if (re == null) return;
    // Convert the global tap position to local coordinates relative to the
    // render editor's top-left, accounting for the scroll offset.
    final localPos = re.globalToLocal(details.globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final scrolledLocal = localPos + Offset(0, scrollOffset);
    final position = re.positionForOffset(scrolledLocal);
    _updateValue(
      _value.copyWith(
        selection: TextSelection.collapsed(offset: position.offset),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final re = _renderEditor;
    if (re == null) return;
    final localPos = re.globalToLocal(details.globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final scrolledLocal = localPos + Offset(0, scrollOffset);
    final position = re.positionForOffset(scrolledLocal);
    _updateValue(
      _value.copyWith(
        selection: _value.selection.copyWith(extentOffset: position.offset),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final textStyle =
        widget.config.textStyle ?? DefaultTextStyle.of(context).style;
    final padding = widget.config.contentPadding;

    final selectionStyle = DefaultSelectionStyle.of(context);
    final cursorColor =
        selectionStyle.cursorColor ?? Theme.of(context).colorScheme.primary;
    final selectionColor = selectionStyle.selectionColor ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.4);

    final renderWidget = QuikiRenderWidget(
      key: _renderKey,
      value: _value,
      textStyle: textStyle,
      padding: padding,
      focused: widget.focusNode.hasFocus,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
    );

    final scrollable = SingleChildScrollView(
      controller: _scrollController,
      child: renderWidget,
    );

    final gestureDetector = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: _onTapDown,
      onPanUpdate: _onPanUpdate,
      child: scrollable,
    );

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: gestureDetector,
    );
  }
}
