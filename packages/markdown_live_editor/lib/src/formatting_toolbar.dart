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
        // Wrapped in a horizontal scroll view so the toolbar remains fully
        // reachable by drag/swipe when its buttons are wider than the
        // viewport (e.g. phone-width screens). `mainAxisSize: min` on the
        // Row is required here: a horizontal SingleChildScrollView gives
        // its child unbounded width, and a MainAxisSize.max Row (the
        // default) cannot lay out under unbounded width constraints.
        //
        // A bare SingleChildScrollView shrink-wraps to its content's
        // natural width when that's narrower than the viewport, which
        // would let an ambient centered/stretched parent reposition the
        // toolbar and change today's flush-left layout. The LayoutBuilder
        // + ConstrainedBox(minWidth: ...) forces the row to still fill the
        // full available width in that case (so it looks and behaves
        // exactly as before), while only growing past that — and becoming
        // scrollable — once content genuinely overflows. This is
        // content-width-driven, not tied to the current button count, so
        // it stays correct as buttons are added or removed.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                      icon: const Icon(LucideIcons.code),
                      tooltip: 'Inline code',
                      onPressed: () => controller.wrapSelection('`', '`'),
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
                      onPressed: controller.toggleCheckboxList,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.indentIncrease),
                      tooltip: 'Indent',
                      onPressed: controller.indent,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.indentDecrease),
                      tooltip: 'Dedent',
                      onPressed: controller.dedent,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
