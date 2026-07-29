import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_config.dart';
import 'indent_dedent.dart';
import 'md_parser.dart';
import 'quiki_render_editor.dart';
import 'render_model.dart';

/// True when running on a mobile platform (Android or iOS).
///
/// iOS builds are deferred but the codebase must remain iOS-compatible;
/// guard all mobile-specific behaviours with this helper rather than
/// Platform.isAndroid alone.
bool get _isMobile => Platform.isAndroid || Platform.isIOS;

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
    this.plainTextMode = false,
    this.imageLoader,
    this.onLinkTap,
    this.onCheckboxToggle,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final MarkdownEditorConfig config;
  final ValueChanged<String>? onChanged;

  /// When true, skip markdown parsing and render source characters as-is.
  /// No reveal/collapse, no delimiter hiding, no glyph substitution.
  final bool plainTextMode;

  /// Optional callback to resolve image paths to raw bytes.  Threaded from
  /// [MarkdownEditor] through to [QuikiEditorState], which manages the
  /// per-path image load cache and passes loaded [dart:ui.Image] objects to
  /// [QuikiRenderWidget] for painting.
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

  // Selection toolbar — shown on mobile after a long-press word-select.
  // ContextMenuController manages the OverlayEntry lifecycle correctly
  // alongside Flutter's own context menus.
  final ContextMenuController _toolbarController = ContextMenuController();

  // Parse cache — re-parsed only when text changes.
  String _lastParsedText = '';
  List<MdElement> _elements = const [];

  // ---------------------------------------------------------------------------
  // Image load cache.
  //
  // Keys are the raw path strings from the markdown source.  Values are the
  // decoded dart:ui.Image, or null when the load failed / returned no bytes.
  //
  // Strategy: keep the cache keyed by path.  When a path is seen for the first
  // time (not in the cache), kick off an async load via widget.imageLoader.
  // When the Future completes call setState() so the render pass picks up the
  // newly decoded image.  The paint pass must never block — it reads from this
  // cache synchronously.
  //
  // The cache is NOT cleared between QuKi switches (setValue calls) so images
  // from the previous note may linger.  For v1 this is acceptable; a size-
  // bounded LRU cache can be added later if needed.
  // ---------------------------------------------------------------------------
  // Image load cache: path → decoded dart:ui.Image (null = failed/placeholder).
  // Always replaced with a new map instance on update so the QuikiRenderEditor
  // setter's identical() check detects the change and marks the render object
  // dirty. Never mutated in place.
  Map<String, ui.Image?> _imageCache = {};
  final Set<String> _loadingPaths = {};

  void _ensureImageLoaded(String path) {
    if (_imageCache.containsKey(path) || _loadingPaths.contains(path)) return;
    final loader = widget.imageLoader;
    if (loader == null) {
      // No loader provided — record null immediately so we show placeholder.
      _imageCache = {..._imageCache, path: null};
      return;
    }
    _loadingPaths.add(path);
    loader(path).then((bytes) async {
      if (!mounted) return;
      ui.Image? image;
      if (bytes != null && bytes.isNotEmpty) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        image = frame.image;
      }
      if (!mounted) return;
      // Replace the map with a new instance so the render object setter's
      // identical() check detects the change and calls markNeedsLayout().
      setState(() {
        _imageCache = {..._imageCache, path: image};
        _loadingPaths.remove(path);
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _imageCache = {..._imageCache, path: null};
        _loadingPaths.remove(path);
      });
    });
  }

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
    _toolbarController.remove();
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
    // Invariant: after any code path that modifies the canonical editing value
    // in response to an IME event — including modifications made by controller
    // listeners (e.g. list auto-continue) that fire synchronously inside
    // _updateValue — the IME must receive a setEditingState call with the
    // final canonical value before the next IME input arrives.
    //
    // _updateValue reads back _value from the controller after listeners have
    // run, so _value here is the post-auto-continue canonical value. Sending
    // it to the IME keeps both sides in sync and prevents the prefix from
    // vanishing when the user starts typing on the newly created list line.
    _connection?.setEditingState(_value);
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
  void showToolbar() {
    _showSelectionToolbar();
  }

  /// Whether the selection toolbar is currently visible.
  ///
  /// Exposed for widget tests only — do not use in production code.
  @visibleForTesting
  bool get isToolbarShown => _toolbarController.isShown;

  /// Forces the selection toolbar to appear regardless of platform.
  ///
  /// Exposed for widget tests that simulate the mobile long-press scenario on
  /// a desktop test host where [_isMobile] is always false.  Do not call this
  /// from production code.
  @visibleForTesting
  void showToolbarForTesting() => _showSelectionToolbar(skipMobileCheck: true);

  // Thin @visibleForTesting wrappers so clipboard operation tests can invoke
  // the private methods without going through gesture simulation.

  @visibleForTesting
  void copySelectionForTesting() => _copySelection();

  @visibleForTesting
  void cutSelectionForTesting() => _cutSelection();

  @visibleForTesting
  void pasteFromClipboardForTesting() => _pasteFromClipboard();

  @visibleForTesting
  void selectAllForTesting() => _selectAll();

  // -------------------------------------------------------------------------
  // Selection toolbar — mobile only.
  //
  // Shown after a long-press produces a non-collapsed selection.
  // Uses ContextMenuController so Flutter's overlay lifecycle is managed
  // correctly alongside any system context menus.
  //
  // Anchor: positioned above the selection start.  getOffsetForCaret returns a
  // local caret offset relative to the text origin (no padding); localToGlobal
  // converts to screen coordinates.  TextSelectionToolbarAnchors handles
  // screen-edge avoidance automatically.
  // -------------------------------------------------------------------------

  void _showSelectionToolbar({bool skipMobileCheck = false}) {
    if (!skipMobileCheck && !_isMobile) return;
    if (!_value.selection.isValid) return;

    final re = _renderEditor;
    if (re == null) return;

    final isCollapsed = _value.selection.isCollapsed;

    // For a collapsed selection use the cursor position as both anchors.
    // For a non-collapsed selection anchor above the selection start and below
    // the selection end so the toolbar avoids overlapping the highlighted text.
    final anchorOffset =
        isCollapsed ? _value.selection.baseOffset : _value.selection.start;

    // Compute the global position above the selection start (or cursor).
    final caretLocalOffset =
        re.getOffsetForCaret(TextPosition(offset: anchorOffset));
    // Add padding.topLeft to convert from text-painter space to render-object
    // local space, then use localToGlobal for screen coordinates.
    final localCaretOffset = caretLocalOffset + re.localPadding.topLeft;
    final globalCaretOffset = re.localToGlobal(localCaretOffset);

    // primaryAnchor: just above the selection start (toolbar prefers to appear
    // above the selection; AdaptiveTextSelectionToolbar flips to below when
    // there is insufficient space).
    final primaryAnchor = Offset(
      globalCaretOffset.dx,
      globalCaretOffset.dy,
    );

    // secondaryAnchor: below the selection end (or cursor) as fallback.
    final endOffset =
        isCollapsed ? _value.selection.baseOffset : _value.selection.end;
    final caretEndLocalOffset =
        re.getOffsetForCaret(TextPosition(offset: endOffset));
    final localEndOffset = caretEndLocalOffset + re.localPadding.topLeft;
    final globalEndOffset = re.localToGlobal(localEndOffset);
    final secondaryAnchor = Offset(
      globalEndOffset.dx,
      globalEndOffset.dy + re.preferredLineHeight,
    );

    _toolbarController.show(
      context: context,
      contextMenuBuilder: (ctx) {
        // Collapsed selection: Paste and Select All only.
        // Non-collapsed selection: Cut, Copy, Paste, Select All.
        final buttonItems = [
          if (!isCollapsed)
            ContextMenuButtonItem(
              label: 'Cut',
              onPressed: () {
                _toolbarController.remove();
                _cutSelection();
              },
            ),
          if (!isCollapsed)
            ContextMenuButtonItem(
              label: 'Copy',
              onPressed: () {
                _toolbarController.remove();
                _copySelection();
              },
            ),
          ContextMenuButtonItem(
            label: 'Paste',
            onPressed: () {
              _toolbarController.remove();
              _pasteFromClipboard();
            },
          ),
          ContextMenuButtonItem(
            label: 'Select All',
            onPressed: () {
              _selectAll();
              // Re-show the toolbar immediately: selection is now non-collapsed
              // (full text selected) so Cut, Copy, Paste, Select All appear.
              _showSelectionToolbar(skipMobileCheck: skipMobileCheck);
            },
          ),
        ];

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(
            primaryAnchor: primaryAnchor,
            secondaryAnchor: secondaryAnchor,
          ),
          buttonItems: buttonItems,
        );
      },
    );
  }

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

    // Tab / Shift+Tab trigger the same Indent/Dedent action as the
    // FormattingToolbar buttons (ADR-34 Stage 4 / #77) — see
    // indent_dedent.dart for the full per-line-kind rule set. Both this key
    // handler and MarkdownEditorController.indent()/dedent() call the same
    // applyIndent/applyDedent functions so button and keystroke are
    // guaranteed to produce identical results for identical starting state.
    if (key == LogicalKeyboardKey.tab) {
      if (shift) {
        _applyDedent();
      } else {
        _applyIndent();
      }
      return KeyEventResult.handled;
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

  /// Applies [applyIndent] to the current text/selection and commits the
  /// result. Shared with [MarkdownEditorController.indent] via the pure
  /// function in indent_dedent.dart — see that file for the full behaviour.
  void _applyIndent() {
    if (!_sel.isValid) return;
    final result = applyIndent(_text, _sel);
    _updateValue(
      TextEditingValue(text: result.text, selection: result.selection),
      notify: true,
    );
    _connection?.setEditingState(_value);
  }

  /// Applies [applyDedent] to the current text/selection and commits the
  /// result. Shared with [MarkdownEditorController.dedent] via the pure
  /// function in indent_dedent.dart — see that file for the full behaviour.
  void _applyDedent() {
    if (!_sel.isValid) return;
    final result = applyDedent(_text, _sel);
    _updateValue(
      TextEditingValue(text: result.text, selection: result.selection),
      notify: true,
    );
    _connection?.setEditingState(_value);
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
    // Dismiss the selection toolbar on any new tap.
    _toolbarController.remove();

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

    // Link tap detection: if the tap lands on a collapsed link, call
    // onLinkTap and do NOT move the cursor.
    final linkUrl = re.linkUrlForOffset(localPos);
    if (linkUrl != null) {
      widget.onLinkTap?.call(linkUrl);
      return;
    }

    // Checkbox tap detection: if the tap lands on a collapsed ☐/☑ glyph,
    // call onCheckboxToggle with the source offset and do NOT move the cursor.
    final checkboxSrcOffset = re.checkboxSourceOffsetForTap(localPos);
    if (checkboxSrcOffset != null) {
      widget.onCheckboxToggle?.call(checkboxSrcOffset);
      return;
    }

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
    // On mobile, show the selection toolbar when a non-collapsed word selection
    // resulted from the long press.  Do NOT call _connection?.show() here —
    // reopening the keyboard after a long-press select is wrong on Android.
    // On desktop, keyboard shortcuts cover all clipboard operations; no toolbar
    // is needed.
    _showSelectionToolbar();
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

    // Re-parse only when text changed and markdown rendering is active.
    // In plain-text mode skip parsing entirely — the element list stays empty
    // so RenderModel produces an identity mapping with no substitutions.
    // Reset _lastParsedText when entering plain-text mode so that returning
    // to styled mode always triggers a fresh parse regardless of text content.
    if (!widget.plainTextMode && _value.text != _lastParsedText) {
      _lastParsedText = _value.text;
      _elements = MdParser.parse(_value.text);
    } else if (widget.plainTextMode) {
      _lastParsedText = ''; // force re-parse when styled mode is restored
      _elements = const [];
    }

    final renderModel = RenderModel.build(
      source: _value.text,
      elements: _elements,
      // In plain-text mode pass cursorOffset = -1 so no element is ever
      // revealed — but since _elements is empty this has no effect.
      cursorOffset: widget.plainTextMode
          ? -1
          : (_value.selection.isValid ? _value.selection.baseOffset : -1),
      baseStyle: textStyle,
    );

    // Kick off loads for any collapsed image slots in the current render model.
    // This is idempotent — _ensureImageLoaded is a no-op for already-loaded or
    // in-flight paths.
    for (final slot in renderModel.imageSlots) {
      _ensureImageLoaded(slot.element.imagePath);
    }

    final renderWidget = QuikiRenderWidget(
      key: _renderKey,
      renderModel: renderModel,
      selection: _value.selection,
      padding: padding,
      focused: widget.focusNode.hasFocus,
      cursorColor: cursorColor,
      selectionColor: selectionColor,
      imageCache: _imageCache,
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
