import 'package:flutter/material.dart';

import 'editor_config.dart';

// Controller held by the host widget (e.g. EditorScreen).
// Lives in this file so it shares the library scope with _MarkdownEditorState
// — required for private member access across Dart's per-file privacy boundary.
class MarkdownEditorController {
  _MarkdownEditorState? _state;

  void _attach(_MarkdownEditorState state) => _state = state;
  void _detach() => _state = null;

  String get currentValue => _state?._textController.text ?? '';
  void setValue(String value) => _state?.setValue(value);

  // Stage 1: always plain-text; toggle is a no-op.
  bool get plainTextMode => true;
  void togglePlainTextMode() {}
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

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue);
    widget.controller?._attach(this);
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _textController.dispose();
    super.dispose();
  }

  void setValue(String value) {
    if (_textController.text != value) {
      _textController.value = TextEditingValue(text: value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _textController,
      focusNode: widget.focusNode,
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
