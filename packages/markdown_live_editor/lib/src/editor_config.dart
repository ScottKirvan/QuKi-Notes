import 'package:flutter/material.dart';

class MarkdownEditorConfig {
  const MarkdownEditorConfig({
    this.textStyle,
    this.contentPadding = const EdgeInsets.all(16),
  });
  final TextStyle? textStyle;
  final EdgeInsets contentPadding;
}
