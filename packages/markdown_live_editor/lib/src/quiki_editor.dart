import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_config.dart';
import 'md_parser.dart';
import 'quiki_render_editor.dart';
import 'render_model.dart';

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

  // Bug 2: track which pointer kind initiated the current gesture so pan-to-
  // select is restricted to mouse/stylus and touch gets normal scroll behaviour.
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.touch;

  // Bug 4: anchor offset for long-press word selection.
  int? _longPressAnchor;

  // Parse cache — re-parsed only when text changes.
  String _lastParsedText = '';
  List<MdElement> _elements = const [];

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
    // Bug 3: when Android dismisses the keyboard, the connection is gone but
    // the FocusNode stays focused. Unfocus so the cursor disappears and a
    // subsequent tap re-enters edit mode cleanly via _onFocusChanged.
    _connection = null;
    widget.focusNode.unfocus();
    if (mounted) setState(() {});
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
  // Tap and long-press handling
  // -------------------------------------------------------------------------

  void _onTapDown(TapDownDetails details) {
    // Bug 3: handle all focus/connection states so the keyboard is always
    // shown after a tap regardless of how the previous session ended.
    if (!widget.focusNode.hasFocus) {
      // _onFocusChanged fires → _openConnection → show().
      widget.focusNode.requestFocus();
    } else if (_connection == null || !_connection!.attached) {
      // Focus held but connection was closed (e.g. Android dismiss button).
      _openConnection();
    } else {
      // Connection open but keyboard may be hidden — re-show.
      _connection!.show();
    }

    final re = _renderEditor;
    if (re == null) return;
    // Bug 1: globalToLocal already accounts for the scroll translation baked
    // into the render tree — do NOT add scrollOffset again.
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    _updateValue(
      _value.copyWith(
        selection: TextSelection.collapsed(offset: position.offset),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Bug 2: touch drags scroll; only mouse/stylus drags extend the selection.
    if (_lastPointerKind != PointerDeviceKind.mouse &&
        _lastPointerKind != PointerDeviceKind.stylus) {
      return;
    }
    final re = _renderEditor;
    if (re == null) return;
    // Bug 1: no scroll offset correction — globalToLocal handles it.
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    _updateValue(
      _value.copyWith(
        selection: _value.selection.copyWith(extentOffset: position.offset),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  // Bug 4: long-press selects the word under the finger (touch only).
  void _onLongPressStart(LongPressStartDetails details) {
    final re = _renderEditor;
    if (re == null) return;
    // Bug 1 fix applied: no scroll offset.
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    final wordSel = _selectWordAt(position.offset);
    _longPressAnchor = wordSel.baseOffset;
    _updateValue(_value.copyWith(selection: wordSel), notify: false);
    _connection?.setEditingState(_value);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final re = _renderEditor;
    if (re == null || _longPressAnchor == null) return;
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    final anchor = _longPressAnchor!;
    final extent = position.offset;
    final sel = extent >= anchor
        ? TextSelection(baseOffset: anchor, extentOffset: extent)
        : TextSelection(baseOffset: extent, extentOffset: anchor);
    _updateValue(_value.copyWith(selection: sel), notify: false);
    _connection?.setEditingState(_value);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _longPressAnchor = null;
    // Ask the IME to show the copy/paste toolbar.
    _connection?.show();
  }

  TextSelection _selectWordAt(int offset) {
    final text = _value.text;
    if (text.isEmpty) return TextSelection.collapsed(offset: offset);
    int start = offset;
    while (start > 0 && _isWordChar(text[start - 1])) {
      start--;
    }
    int end = offset;
    while (end < text.length && _isWordChar(text[end])) {
      end++;
    }
    if (start == end) return TextSelection.collapsed(offset: offset);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  bool _isWordChar(String c) => RegExp(r'\w').hasMatch(c);

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

    // Re-parse only when text changed; element list is cached across frames.
    if (_value.text != _lastParsedText) {
      _lastParsedText = _value.text;
      _elements = MdParser.parse(_value.text);
    }

    final renderModel = RenderModel.build(
      source: _value.text,
      elements: _elements,
      cursorOffset: _value.selection.isValid ? _value.selection.baseOffset : -1,
      baseStyle: textStyle,
    );

    final renderWidget = QuikiRenderWidget(
      key: _renderKey,
      renderModel: renderModel,
      selection: _value.selection,
      padding: padding,
      focused: widget.focusNode.hasFocus,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
    );

    final scrollable = SingleChildScrollView(
      controller: _scrollController,
      child: renderWidget,
    );

    // Bug 2: track pointer device kind so _onPanUpdate can gate on mouse/stylus.
    final gestureDetector = Listener(
      onPointerDown: (e) => _lastPointerKind = e.kind,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: _onTapDown,
        onPanUpdate: _onPanUpdate,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: scrollable,
      ),
    );

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: gestureDetector,
    );
  }
}
