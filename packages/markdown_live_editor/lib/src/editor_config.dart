import 'package:flutter/material.dart';

class MarkdownEditorConfig {
  const MarkdownEditorConfig({
    this.textStyle,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
  });
  final TextStyle? textStyle;
  final EdgeInsets contentPadding;
}
