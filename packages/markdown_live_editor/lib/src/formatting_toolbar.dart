import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'markdown_editor.dart';

class FormattingToolbar extends StatelessWidget {
  const FormattingToolbar({super.key, required this.controller});

  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.bold),
              tooltip: 'Bold',
              onPressed: () => controller.wrapSelection('**', '**'),
            ),
            IconButton(
              icon: const Icon(LucideIcons.italic),
              tooltip: 'Italic',
              onPressed: () => controller.wrapSelection('_', '_'),
            ),
            IconButton(
              icon: const Icon(LucideIcons.strikethrough),
              tooltip: 'Strikethrough',
              onPressed: () => controller.wrapSelection('~~', '~~'),
            ),
            IconButton(
              icon: const Icon(LucideIcons.heading1),
              tooltip: 'Heading',
              onPressed: () => controller.toggleLinePrefix('# '),
            ),
            IconButton(
              icon: const Icon(LucideIcons.list),
              tooltip: 'Unordered list',
              onPressed: controller.toggleUnorderedList,
            ),
            IconButton(
              icon: const Icon(LucideIcons.listOrdered),
              tooltip: 'Ordered list',
              onPressed: controller.toggleOrderedList,
            ),
            IconButton(
              icon: const Icon(LucideIcons.listChecks),
              tooltip: 'Task list',
              onPressed: () => controller.toggleLinePrefix('- [ ] '),
            ),
            const Spacer(),
            if (Platform.isAndroid || Platform.isIOS)
              IconButton(
                icon: const Icon(LucideIcons.keyboardOff),
                tooltip: 'Dismiss keyboard',
                onPressed: controller.dismissKeyboard,
              ),
          ],
        ),
      ),
    );
  }
}
