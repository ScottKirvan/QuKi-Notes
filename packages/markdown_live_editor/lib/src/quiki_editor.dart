import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_config.dart';
import 'html_paste.dart';
import 'indent_dedent.dart';
import 'md_parser.dart';
import 'quiki_render_editor.dart';
import 'render_model.dart';
import 'selection_handle.dart';

/// Test-only override forcing [_isMobile] to true regardless of the actual
/// platform. Widget tests run on a desktop/CI host, where [_isMobile] is
/// always false — this lets a test exercise mobile-only affordances
/// (selection toolbar, selection handles) via the same real gesture path
/// production code takes, rather than a `ForTesting` bypass that skips the
/// gating logic entirely. See [QuikiEditorState.debugForceMobile].
bool _debugForceMobile = false;

/// True when running on a mobile platform (Android or iOS), or when a test
/// has set [QuikiEditorState.debugForceMobile].
///
/// iOS builds are deferred but the codebase must remain iOS-compatible;
/// guard all mobile-specific behaviours with this helper rather than
/// Platform.isAndroid alone.
bool get _isMobile => Platform.isAndroid || Platform.isIOS || _debugForceMobile;

// ---------------------------------------------------------------------------
// _ActiveHandleDrag — Stage 2 selection-handle drag bookkeeping.
//
// While a handle is being dragged, the two rendered handle widgets must stay
// glued to (a) the live drag position and (b) the untouched opposite
// boundary — NOT to `selection.start`/`selection.end` directly. Those two
// only coincide with "grabbed handle" / "anchor handle" until the drag
// crosses the opposite boundary, at which point `.start`/`.end` swap which
// physical side they refer to but the ACTIVE GestureDetector (bound to a
// pointer, not a screen position) keeps receiving events for the same
// widget it started on. Rendering straight from `.start`/`.end` mid-drag
// would make the handle under the user's finger visually snap away the
// instant a crossing happens. Tracking (fixed, moving) explicitly instead —
// and rendering from those while a drag is active — keeps the dragged handle
// glued to the pointer through a crossing, and the other handle pinned at
// its untouched anchor, exactly matching what the finger is actually doing.
// ---------------------------------------------------------------------------

class _ActiveHandleDrag {
  const _ActiveHandleDrag({
    required this.isStartRole,
    required this.fixed,
    required this.moving,
  });

  /// True when the user grabbed the handle that was rendered at
  /// `selection.start` at the moment the drag began. Fixed for the whole
  /// drag — it identifies which of the two handle widgets is live, not which
  /// numeric boundary is currently smaller (those can swap on a crossing).
  final bool isStartRole;

  /// The source offset of the boundary NOT being dragged, captured once at
  /// drag-start. Never changes for the duration of this drag.
  final int fixed;

  /// The live, continuously-updated source offset of the boundary being
  /// dragged, resolved from the pointer's current position on every update.
  final int moving;

  _ActiveHandleDrag copyWith({int? moving}) => _ActiveHandleDrag(
        isStartRole: isStartRole,
        fixed: fixed,
        moving: moving ?? this.moving,
      );
}

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

  // Selection-handle-overlay rebuild trigger — see _onScrollChangedForHandles
  // for why this exists instead of the overlay's AnimatedBuilder listening to
  // _scrollController directly.
  final ValueNotifier<int> _handleOverlayTick = ValueNotifier<int>(0);
  bool _handleOverlayRebuildScheduled = false;

  // Root cause of a real, confirmed device bug (handle drag not grabbing —
  // touch fell through to the underlying scrollable content instead): a
  // ScrollPosition fires notifyListeners() SYNCHRONOUSLY at the moment
  // `.pixels` changes — i.e. within the same call stack as the pointer/
  // ballistic-scroll event that changed it, which is BEFORE that frame's
  // layout phase runs. _buildSelectionHandlesOverlay computes each handle's
  // screen position via QuikiRenderEditor.localToGlobal, which reads the
  // render tree's CURRENT paint transform — and that transform is only
  // updated to reflect the new scroll offset during THIS frame's upcoming
  // layout pass, which hasn't happened yet at the moment a scroll-triggered
  // rebuild's build() method runs. So a rebuild driven directly off a scroll
  // notification always computes handle positions one scroll-tick stale.
  // During continuous scrolling this stayed imperceptible (each tick's error
  // was quickly superseded by the next), but the LAST notification before
  // scrolling comes to rest suffers the exact same staleness with nothing
  // afterward to correct it — confirmed via a widget test that scrolls, lets
  // the scroll settle, and compares the rendered handle's actual position
  // against a position independently computed from
  // QuikiRenderEditor.getOffsetForCaret fresh (outside any widget rebuild):
  // driving the overlay off _scrollController directly left the two positions
  // measurably apart (tens of px) even after the scroll had fully stopped —
  // the mismatch never self-corrected because nothing but a scroll
  // notification ever triggered another overlay rebuild.
  //
  // Fix: don't rebuild the overlay directly off _scrollController's
  // notification. Instead, schedule a WidgetsBinding.instance.
  // addPostFrameCallback the first time a scroll notification arrives for a
  // given frame (the `_handleOverlayRebuildScheduled` guard collapses any
  // further notifications in that same frame into the one callback), and only
  // bump _handleOverlayTick — which is what the overlay's AnimatedBuilder
  // actually listens to — from inside that callback. A post-frame callback
  // runs strictly after the frame's layout and paint have both completed, so
  // by the time _handleOverlayTick's own listener notification triggers the
  // NEXT frame's overlay rebuild, QuikiRenderEditor's paint transform already
  // reflects the scroll offset that was current as of the frame just
  // finished — no scroll delta remains unaccounted for once scrolling stops,
  // since that scenario's final notification gets the same deferred, now-
  // accurate treatment as every other tick.
  void _onScrollChangedForHandles() {
    if (_handleOverlayRebuildScheduled) return;
    _handleOverlayRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleOverlayRebuildScheduled = false;
      if (!mounted) return;
      _handleOverlayTick.value++;
    });
  }

  // ADR-35: reads the clipboard's HTML representation for _pasteFromClipboard.
  // Defaults to the real quill_native_bridge-backed implementation.
  // Overridable via debugClipboardHtmlReader for tests, since
  // quill_native_bridge's native plugin channel — unlike Clipboard.getData's
  // platform channel — is not available under `flutter test`.
  static ClipboardHtmlReader _clipboardHtmlReader = readClipboardHtml;

  /// Test-only override for the clipboard HTML reader used by
  /// [_pasteFromClipboard]. Pass null to restore the real
  /// quill_native_bridge-backed implementation.
  @visibleForTesting
  static set debugClipboardHtmlReader(ClipboardHtmlReader? reader) {
    _clipboardHtmlReader = reader ?? readClipboardHtml;
  }

  // Bug 2: track which pointer kind initiated the current gesture so pan-to-
  // select is restricted to mouse/stylus and touch gets normal scroll behaviour.
  PointerDeviceKind _lastPointerKind = PointerDeviceKind.touch;

  // Bug 4: anchor offset for long-press word selection.
  int? _longPressAnchor;

  // Recognizer hardening: explicit anchor offset for mouse/stylus
  // drag-to-select, captured at drag-start rather than inherited implicitly
  // from whatever _onTapDown last left in _value.selection.baseOffset. See
  // _onPanStart.
  int? _panAnchor;

  // Selection toolbar — shown on mobile after a long-press word-select.
  // ContextMenuController manages the OverlayEntry lifecycle correctly
  // alongside Flutter's own context menus.
  final ContextMenuController _toolbarController = ContextMenuController();

  // Stage 2: selection handles. Non-null for the entire duration of an
  // active handle drag (set in onPanStart, cleared in onPanEnd) — see
  // _ActiveHandleDrag's doc comment for why rendering must consult this
  // instead of selection.start/selection.end while a drag is in progress.
  _ActiveHandleDrag? _activeHandleDrag;

  /// Visible handle glyph diameter — approximates selection.md §2's ~22dp.
  static const double _handleDiameter = 20.0;

  /// Touch-hit box side length — approximates selection.md §2's ~48dp
  /// minimum recommended touch target, centered around the visible glyph.
  static const double _handleHitBoxSize = 44.0;

  static const double _handleInset = (_handleHitBoxSize - _handleDiameter) / 2;

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

  /// Key for the Stack that directly contains the Stage 2 selection-handle
  /// Positioned widgets (see build()'s doc comment for why this is a
  /// separate overlay Stack, not nested inside the scrollable content) —
  /// resolved to a RenderBox so handle positions can be converted from
  /// QuikiRenderEditor's local coordinate space via
  /// globalToLocal/localToGlobal, the same pattern _showSelectionToolbar
  /// already uses to anchor the toolbar.
  final GlobalKey _handleOverlayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _value = widget.controller.value;
    widget.controller.addListener(_onControllerChanged);
    widget.focusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScrollChangedForHandles);
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
    _scrollController.removeListener(_onScrollChangedForHandles);
    _connection?.close();
    _scrollController.dispose();
    _handleOverlayTick.dispose();
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

  /// Forces [_isMobile] to true regardless of the actual platform, for the
  /// lifetime of the test process (or until reset back to false).
  ///
  /// Unlike [showToolbarForTesting]'s one-shot bypass, this flips the same
  /// gate production code checks, so a test can drive a real gesture (a real
  /// long-press, a real drag on a handle widget) end-to-end exactly as it
  /// would happen on a mobile device, including handles actually appearing
  /// in the widget tree for `tester.drag`/`startGesture` to act on. Do not
  /// call from production code.
  @visibleForTesting
  static set debugForceMobile(bool value) => _debugForceMobile = value;

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

  // ADR-35: when the clipboard carries an HTML representation, convert it to
  // GFM markdown and insert that instead of the plain-text representation —
  // through this exact same buffer-update path (single edit, same selection-
  // replace semantics, same undo behavior). plainTextMode is irrelevant here:
  // it only controls how the existing buffer is rendered, not how paste
  // writes to it.
  void _pasteFromClipboard() {
    _readClipboardHtmlSafely().then((html) {
      if (!mounted) return;
      if (html != null && html.trim().isNotEmpty) {
        final markdown = convertHtmlToMarkdown(html);
        if (markdown.isNotEmpty) {
          _insertAtSelection(markdown);
          return;
        }
      }
      // No HTML representation on the clipboard (or conversion produced
      // nothing usable) — identical to pre-ADR-35 behavior: read the plain-
      // text representation.
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        if (data?.text == null || !mounted) return;
        _insertAtSelection(data!.text!);
      });
    });
  }

  // The real quill_native_bridge-backed reader can throw (confirmed under
  // `flutter test`, where its native plugin channel is unregistered, but the
  // same class of failure — a misbehaving platform channel, an unsupported
  // clipboard content type, a permission prompt rejected by the user, etc. —
  // is a real possibility on any platform in production too). Paste must
  // never surface that as a crash: any failure reading the HTML
  // representation is treated exactly like "no HTML representation present"
  // and falls back to the plain-text path.
  Future<String?> _readClipboardHtmlSafely() async {
    try {
      return await _clipboardHtmlReader();
    } catch (_) {
      return null;
    }
  }

  void _insertAtSelection(String text) {
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

  // Recognizer hardening: the drag's anchor is now captured explicitly here,
  // at drag-start, rather than being inherited implicitly from whatever
  // _onTapDown last left in _value.selection.baseOffset. That prior
  // arrangement worked only because _onTapDown happens to always run first
  // in the same gesture sequence — an ordering assumption, not a guarantee —
  // and DragStartDetails.globalPosition is not even guaranteed to equal the
  // original pointer-down position (a pan recognizer only starts once
  // movement exceeds the touch/mouse slop, so its own start position can sit
  // a few pixels from the true down point). Mirrors how long-press already
  // captures its own anchor via _longPressAnchor.
  void _onPanStart(DragStartDetails details) {
    // Bug 2: touch drags scroll; only mouse/stylus drags anchor a selection.
    if (_lastPointerKind != PointerDeviceKind.mouse &&
        _lastPointerKind != PointerDeviceKind.stylus) {
      _panAnchor = null;
      return;
    }
    final re = _renderEditor;
    if (re == null) return;
    final localPos = re.globalToLocal(details.globalPosition);
    _panAnchor = re.positionForOffset(localPos).offset;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Bug 2: touch drags scroll; only mouse/stylus drags extend the selection.
    if (_lastPointerKind != PointerDeviceKind.mouse &&
        _lastPointerKind != PointerDeviceKind.stylus) {
      return;
    }
    final anchor = _panAnchor;
    if (anchor == null) return;
    final re = _renderEditor;
    if (re == null) return;
    // Bug 1: no scroll offset correction — globalToLocal handles it.
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    _updateValue(
      _value.copyWith(
        selection:
            TextSelection(baseOffset: anchor, extentOffset: position.offset),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _onPanEnd(DragEndDetails details) {
    _panAnchor = null;
  }

  // Bug 4: long-press selects the entity under the finger (touch only).
  // Double-tap (_onDoubleTapDown, below) shares this exact same
  // determination — both are just different gesture entry points into
  // _selectEntityAt, so they can never drift apart.
  void _onLongPressStart(LongPressStartDetails details) {
    final re = _renderEditor;
    if (re == null) return;
    // Bug 1 fix applied: no scroll offset.
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    final entitySel = _selectEntityAt(position.offset);
    _longPressAnchor = entitySel.baseOffset;
    _updateValue(_value.copyWith(selection: entitySel), notify: false);
    _connection?.setEditingState(_value);
  }

  // Double-tap: identical underlying word/entity determination as
  // long-press — see _selectEntityAt. Uses Flutter's standard double-tap
  // recognizer as-is; no mitigation is added for the single-tap-commit
  // latency Flutter introduces once a double-tap recognizer shares the
  // gesture arena (an explicit instruction from the project owner — that
  // tradeoff is judged from real device feel in a later round, not solved
  // preemptively here). _onTapDown already ran for this same pointer-down
  // event (it fires optimistically before the arena resolves single vs.
  // double tap), so focus/IME handling is already done by the time this
  // fires — only the selection needs to be overridden.
  void _onDoubleTapDown(TapDownDetails details) {
    final re = _renderEditor;
    if (re == null) return;
    final localPos = re.globalToLocal(details.globalPosition);
    final position = re.positionForOffset(localPos);
    final entitySel = _selectEntityAt(position.offset);
    _updateValue(_value.copyWith(selection: entitySel), notify: false);
    _connection?.setEditingState(_value);
    _showSelectionToolbar();
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

  // -------------------------------------------------------------------------
  // Selection handles — Stage 2 (notes/dev/selection.md §2, ADR-36).
  //
  // Two independent, later, draggable handles at a non-collapsed selection's
  // start and end. Each handle's GestureDetector is its own fresh gesture —
  // unrelated to whatever gesture (long-press, double-tap) created the
  // selection in the first place, so a user can select a word, lift their
  // finger, wait, and come back later to drag either boundary.
  //
  // Drag precision is character-level (positionForOffset resolves to the
  // nearest source character, not a word/entity boundary) even though the
  // selection that produced the handles may have snapped to a whole word —
  // deliberately not routed through _selectEntityAt.
  // -------------------------------------------------------------------------

  /// Resolves a global pointer position to a source-text offset, via the
  /// same globalToLocal → positionForOffset path every other gesture handler
  /// in this class already uses (_onTapDown, _onPanUpdate, etc.) — no new
  /// coordinate math, only a new caller of what already exists.
  int? _sourceOffsetForGlobal(Offset globalPosition) {
    final re = _renderEditor;
    if (re == null) return null;
    final localPos = re.globalToLocal(globalPosition);
    return re.positionForOffset(localPos).offset;
  }

  void _onStartHandlePanStart(DragStartDetails details) {
    final moving = _sourceOffsetForGlobal(details.globalPosition);
    if (moving == null) return;
    // Requirement: the floating toolbar must not sit stuck in a stale
    // position while a handle is actively dragged. Hidden here and re-shown
    // (freshly anchored to the settled selection) in _onStartHandlePanEnd —
    // simpler and less jittery than live-repositioning it every drag update,
    // and matches the platform convention this editor's selection behaviour
    // is otherwise modelled on (Android also hides the floating toolbar for
    // the duration of a handle drag).
    _toolbarController.remove();
    setState(() {
      _activeHandleDrag = _ActiveHandleDrag(
        isStartRole: true,
        fixed: _sel.end,
        moving: moving,
      );
    });
  }

  void _onStartHandlePanUpdate(DragUpdateDetails details) {
    final drag = _activeHandleDrag;
    if (drag == null || !drag.isStartRole) return;
    final moving = _sourceOffsetForGlobal(details.globalPosition);
    if (moving == null) return;
    _activeHandleDrag = drag.copyWith(moving: moving);
    // Deliberately unconditional TextSelection(baseOffset: fixed, extentOffset:
    // moving) — no min/max reordering. TextSelection.start/.end (used by
    // every other reader: highlight painting, textInside, toolbar anchoring)
    // already normalize via min/max regardless of base/extent order, so a
    // drag that pushes `moving` past `fixed` correctly flips which physical
    // boundary is logically start vs end with no special-case crossing logic
    // needed here — see _ActiveHandleDrag's doc comment for why the RENDER
    // POSITIONS of the two handle widgets need their own (fixed, moving)
    // tracking regardless.
    _updateValue(
      _value.copyWith(
        selection: TextSelection(baseOffset: drag.fixed, extentOffset: moving),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _onStartHandlePanEnd(DragEndDetails details) {
    setState(() {
      _activeHandleDrag = null;
    });
    _showSelectionToolbar();
  }

  void _onEndHandlePanStart(DragStartDetails details) {
    final moving = _sourceOffsetForGlobal(details.globalPosition);
    if (moving == null) return;
    _toolbarController.remove();
    setState(() {
      _activeHandleDrag = _ActiveHandleDrag(
        isStartRole: false,
        fixed: _sel.start,
        moving: moving,
      );
    });
  }

  void _onEndHandlePanUpdate(DragUpdateDetails details) {
    final drag = _activeHandleDrag;
    if (drag == null || drag.isStartRole) return;
    final moving = _sourceOffsetForGlobal(details.globalPosition);
    if (moving == null) return;
    _activeHandleDrag = drag.copyWith(moving: moving);
    _updateValue(
      _value.copyWith(
        selection: TextSelection(baseOffset: drag.fixed, extentOffset: moving),
      ),
      notify: false,
    );
    _connection?.setEditingState(_value);
  }

  void _onEndHandlePanEnd(DragEndDetails details) {
    setState(() {
      _activeHandleDrag = null;
    });
    _showSelectionToolbar();
  }

  /// Builds the (start, end) handle widgets for the current selection, or an
  /// empty list when handles should not be shown. Always exactly 0 or 2
  /// entries. Given constant [ValueKey]s so the overlay Stack's child-list
  /// reconciliation always matches them to the same Element/State across
  /// rebuilds — required for GestureDetector's PanGestureRecognizer to
  /// survive a selection crossing mid-drag (see _ActiveHandleDrag's doc
  /// comment).
  ///
  /// Positions are computed via [QuikiRenderEditor.localToGlobal] (a global,
  /// screen-space point — the same call [_showSelectionToolbar] already uses
  /// to anchor the toolbar) and then [RenderBox.globalToLocal] against the
  /// overlay Stack's OWN RenderBox (resolved via [_handleOverlayKey]) rather
  /// than any manual scroll-offset arithmetic — this stays correct through
  /// scrolling, resizing, or any other ancestor transform without this
  /// method needing to know about any of them.
  List<Widget> _buildSelectionHandlesOverlay(Color color) {
    final re = _renderEditor;
    if (re == null) return const [];
    final drag = _activeHandleDrag;
    final sel = _value.selection;
    final showing =
        _isMobile && (drag != null || (sel.isValid && !sel.isCollapsed));
    if (!showing) return const [];

    final overlayBox =
        _handleOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.attached || !overlayBox.hasSize) {
      return const [];
    }

    final int startSourceOffset;
    final int endSourceOffset;
    if (drag == null) {
      startSourceOffset = sel.start;
      endSourceOffset = sel.end;
    } else if (drag.isStartRole) {
      startSourceOffset = drag.moving;
      endSourceOffset = drag.fixed;
    } else {
      startSourceOffset = drag.fixed;
      endSourceOffset = drag.moving;
    }

    Widget buildHandle({
      required Key key,
      required int sourceOffset,
      required bool isStart,
      required GestureDragStartCallback onPanStart,
      required GestureDragUpdateCallback onPanUpdate,
      required GestureDragEndCallback onPanEnd,
    }) {
      // Handles hang below the line, anchored where the caret meets the
      // line's bottom edge — see selection_handle.dart's _HandlePainter doc
      // comment for how the "point" corner is derived from this same anchor.
      final caretLocal =
          re.getOffsetForCaret(TextPosition(offset: sourceOffset)) +
              re.localPadding.topLeft;
      final lineHeight = re.preferredLineHeight;
      final anchorInRenderEditor =
          Offset(caretLocal.dx, caretLocal.dy + lineHeight);
      final anchorGlobal = re.localToGlobal(anchorInRenderEditor);
      final anchor = overlayBox.globalToLocal(anchorGlobal);

      final pointLocal = isStart
          ? const Offset(_handleInset + _handleDiameter, _handleInset)
          : const Offset(_handleInset, _handleInset);
      final topLeft = anchor - pointLocal;
      return Positioned(
        key: key,
        left: topLeft.dx,
        top: topLeft.dy,
        width: _handleHitBoxSize,
        height: _handleHitBoxSize,
        child: SelectionHandle(
          color: color,
          diameter: _handleDiameter,
          pointOnRight: isStart,
          onPanStart: onPanStart,
          onPanUpdate: onPanUpdate,
          onPanEnd: onPanEnd,
        ),
      );
    }

    return [
      buildHandle(
        key: const ValueKey('quiki-selection-handle-start'),
        sourceOffset: startSourceOffset,
        isStart: true,
        onPanStart: _onStartHandlePanStart,
        onPanUpdate: _onStartHandlePanUpdate,
        onPanEnd: _onStartHandlePanEnd,
      ),
      buildHandle(
        key: const ValueKey('quiki-selection-handle-end'),
        sourceOffset: endSourceOffset,
        isStart: false,
        onPanStart: _onEndHandlePanStart,
        onPanUpdate: _onEndHandlePanUpdate,
        onPanEnd: _onEndHandlePanEnd,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Entity-aware selection — shared by long-press and double-tap.
  //
  // Root cause of the previously-shipped partial-word-selection bug: the old
  // implementation (formerly _selectWordAt/_isWordChar here) scanned the raw
  // SOURCE text character-by-character with a \w word-char test. Source text
  // still contains every hidden markdown delimiter — e.g. the '**' around
  // '**bold**', or a mid-word nested-emphasis run like 're**a**lly' (ADR-33).
  // '*' correctly fails the word-char test, so the scan stopped dead at the
  // first hidden delimiter it hit and returned only the fragment of the word
  // on one side of it, even though the delimiter is entirely invisible in
  // rendered view and the user perceives one continuous word. This was
  // reliably reproducible for any word containing or bordering hidden
  // markup, which matches "sometimes" from real-device use — plain
  // undecorated paragraph text was never affected.
  //
  // Fix: scan the RENDERED text (delimiters already stripped — exactly what
  // is on screen) and translate the resulting boundary back to source
  // offsets via RenderModel's existing bidirectional offset maps — the same
  // maps _onTapDown already uses for tap-to-source and _showSelectionToolbar
  // uses for caret positioning. This also naturally produces the required
  // "select word, not delimiters" behaviour for a word immediately bordered
  // by (rather than split by) a delimiter, since the delimiter characters
  // never appear in the rendered string being scanned at all.
  // ---------------------------------------------------------------------------

  /// Matches an email address closely enough for practical selection
  /// purposes (not full RFC 5322): a local part of word chars/./%/+/-, '@',
  /// a domain of word chars/./-, ending in a dot-separated TLD of at least
  /// two letters.
  static final RegExp _emailPattern =
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

  /// Matches a punctuated numeric string — digits combined with the
  /// `. - / ( )` punctuation set (phone numbers, serial/part numbers,
  /// version numbers, dates). Anchored to start AND end on a digit so
  /// ordinary surrounding prose punctuation (a sentence-ending '.', a bare
  /// '(') is never absorbed into the match.
  ///
  /// Deliberately strictly digits-plus-punctuation, with no letters: a
  /// letter-suffixed identifier like 'SN-2024-0847-B' selects only
  /// '2024-0847' here, not the 'SN-' prefix or '-B' suffix (see
  /// selection_test.dart for the demonstrating case). Reasoning: allowing
  /// letters into this character class would turn it from a numeric-token
  /// matcher into a general punctuated-token matcher, which would also
  /// reach ordinary hyphenated/dotted prose ('well-known', 'e.g.',
  /// 'self-contained') — a much bigger behavioural change than "select
  /// whole phone/serial/version numbers", with collateral effects on plain
  /// word selection this task did not ask for. Anchoring strictly on digits
  /// is the narrowest change that still selects the numeric identifier as a
  /// whole; a mixed alnum+punctuation identifier matcher is a reasonable
  /// future ask but a distinct one from what was requested here.
  static final RegExp _numericEntityPattern = RegExp(r'\d(?:[\d.\-/()]*\d)?');

  /// A plain word — letters, digits, underscore.
  static final RegExp _wordPattern = RegExp(r'\w+');

  /// Determines the word/entity that should be selected when a long-press or
  /// double-tap resolves to source offset [sourceOffset], and returns it as
  /// a source [TextSelection]. The single implementation both gestures call.
  TextSelection _selectEntityAt(int sourceOffset) {
    final text = _value.text;
    if (text.isEmpty) return const TextSelection.collapsed(offset: 0);
    final clampedSource = sourceOffset.clamp(0, text.length);

    final re = _renderEditor;
    if (re == null) return TextSelection.collapsed(offset: clampedSource);
    final model = re.renderModel;

    final ri = model.renderedForSource(clampedSource);

    // Links (and bare autolinks) take priority, reusing the same LinkSlot
    // data _onTapDown already relies on for tap-to-navigate — the whole
    // rendered link label is one entity, never re-derived from a URL regex.
    for (final slot in model.linkSlots) {
      if (ri >= slot.renderedStart && ri < slot.renderedEnd) {
        return _renderedRangeToSourceSelection(
            model, slot.renderedStart, slot.renderedEnd);
      }
    }

    final rendered = model.textSpan.toPlainText();
    if (rendered.isEmpty) return TextSelection.collapsed(offset: clampedSource);
    final clampedRi = ri.clamp(0, rendered.length);

    final email = _findEnclosingMatch(_emailPattern, rendered, clampedRi);
    if (email != null) {
      return _renderedRangeToSourceSelection(model, email.start, email.end);
    }
    final numeric =
        _findEnclosingMatch(_numericEntityPattern, rendered, clampedRi);
    if (numeric != null) {
      return _renderedRangeToSourceSelection(model, numeric.start, numeric.end);
    }
    final word = _findEnclosingMatch(_wordPattern, rendered, clampedRi);
    if (word != null) {
      return _renderedRangeToSourceSelection(model, word.start, word.end);
    }

    return TextSelection.collapsed(offset: clampedSource);
  }

  /// Returns the first match of [pattern] in [text] whose range encloses
  /// [offset] (inclusive of both ends, so a tap landing exactly on a match's
  /// boundary character still counts — "on or adjacent to"), or null.
  /// [pattern]'s matches are produced in ascending-start order, so this can
  /// stop as soon as a match starts past [offset].
  ({int start, int end})? _findEnclosingMatch(
      RegExp pattern, String text, int offset) {
    for (final m in pattern.allMatches(text)) {
      if (m.start > offset) break;
      if (offset <= m.end) return (start: m.start, end: m.end);
    }
    return null;
  }

  /// Converts a rendered-offset range `[renderedStart, renderedEnd)` — from
  /// a regex match against the rendered plain text, or from a [LinkSlot] —
  /// into a source [TextSelection], via [RenderModel]'s bidirectional offset
  /// maps.
  ///
  /// Deliberately NOT `model.sourceForRendered(renderedEnd)` for the end
  /// boundary: at the end of a collapsed run (e.g. the last visible
  /// character of a bold word, just before its closing '**'), the
  /// rendered→source map's entry at that exact position can land on the
  /// end-of-source sentinel or the start of unrelated following content
  /// rather than "one past the last matched character" — pulling trailing
  /// hidden delimiters into the selection, exactly what the
  /// whole-word/whole-link invariant forbids. Resolving the LAST matched
  /// rendered character's own source offset and adding 1 always lands
  /// exactly past that character and before any hidden delimiter following
  /// it.
  TextSelection _renderedRangeToSourceSelection(
    RenderModel model,
    int renderedStart,
    int renderedEnd,
  ) {
    if (renderedEnd <= renderedStart) {
      return TextSelection.collapsed(
          offset: model.sourceForRendered(renderedStart));
    }
    final sourceStart = model.sourceForRendered(renderedStart);
    final sourceEnd = model.sourceForRendered(renderedEnd - 1) + 1;
    return TextSelection(baseOffset: sourceStart, extentOffset: sourceEnd);
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
        onDoubleTapDown: _onDoubleTapDown,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: scrollable,
      ),
    );

    final focusable = Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: gestureDetector,
    );

    // Stage 2 selection handles: deliberately rendered as a SEPARATE overlay
    // layer — a sibling of `focusable` in the Stack below, not a descendant
    // of it. A handle's own GestureDetector nested inside the same hit-test
    // path as the editor's Tap/DoubleTap/Pan/LongPress recognizers would put
    // both in the same gesture arena for every pointer-down landing on a
    // handle — precisely the kind of shared-arena ambiguity this stage was
    // warned could ripple unpredictably (see the double-tap-vs-tap latency
    // finding from Stage 1). Kept as a sibling instead: Stack hit-testing
    // stops at the first (topmost) child that claims a hit, so a pointer
    // down inside a handle's hit box is claimed entirely by the handle and
    // never reaches `focusable`'s subtree at all — no ambiguity possible.
    //
    // The tradeoff: handles no longer scroll "for free" as children of the
    // same SingleChildScrollView, so their screen position is recomputed
    // from scratch (via QuikiRenderEditor.localToGlobal → this overlay's own
    // RenderBox.globalToLocal, resolved fresh against the CURRENT live
    // scroll transform on every call — see _buildSelectionHandlesOverlay)
    // inside an AnimatedBuilder, so only this small overlay subtree rebuilds
    // on every scroll tick, not the whole editor. The AnimatedBuilder listens
    // to _handleOverlayTick, NOT _scrollController directly — see
    // _onScrollChangedForHandles for why a direct listen leaves computed
    // handle positions permanently one scroll-tick stale (a real, confirmed
    // drag-grab bug), and why the extra indirection through a post-frame-
    // deferred tick fixes it.
    // StackFit.expand: without it, Stack only loosens (not removes) the
    // incoming constraints for non-positioned children, so `focusable` — no
    // longer forced to a TIGHT size the way it was pre-Stage-2 (as the sole
    // top-level widget under whatever tight/bounded constraints its parent,
    // e.g. Scaffold.body, imposed) — could shrink to its own content height
    // instead of filling the available area, while this Stack's own
    // reported size still expands to fill it (an empty overlay Stack with no
    // non-positioned children of its own sizes to constraints.biggest
    // regardless). The mismatch is exactly what broke
    // clipboard_toolbar_test.dart's "toolbar is dismissed on next tap" during
    // review: a tap at the geometric center of the (larger) reported
    // MarkdownEditor bounds landed below the (smaller, content-sized)
    // focusable area — hitting nothing at all, so _onTapDown never fired.
    // StackFit.expand gives every non-positioned child the Stack's own exact
    // size, restoring the original fill-available-space sizing exactly.
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        focusable,
        AnimatedBuilder(
          animation: _handleOverlayTick,
          builder: (context, _) => Stack(
            clipBehavior: Clip.none,
            key: _handleOverlayKey,
            children: _buildSelectionHandlesOverlay(cursorColor),
          ),
        ),
      ],
    );
  }
}
