import 'package:flutter/material.dart';

class MarkdownEditorConfig {
  const MarkdownEditorConfig({
    this.textStyle,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.syntaxColor,
  });

  final TextStyle? textStyle;
  final EdgeInsets contentPadding;

  /// Color for visible-but-muted syntax markers on the cursor line.
  ///
  /// When the cursor is on a line, syntax characters (e.g. `#`, `**`) are
  /// shown in this color rather than hidden with transparent. Defaults to
  /// [textStyle.color] at 35% opacity when null.
  final Color? syntaxColor;
}
