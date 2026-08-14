import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import 'markdown_editor.dart';

// Tightens the default Material IconButton footprint (48x48 on mobile via
// its invisible tap-target padding, 40x40 on desktop) down to a smaller,
// still-comfortably-tappable size, so adjacent toolbar buttons read as one
// dense group instead of having a large visible gap between them.
// `tapTargetSize: shrinkWrap` removes the mobile-only invisible minimum
// (Android/iOS default to `padded`, which otherwise wins over the smaller
// content-driven size); `minimumSize`/`padding` then set the actual visible
// footprint uniformly across all platforms.
const _tightIconButtonStyle = ButtonStyle(
  padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
  minimumSize: WidgetStatePropertyAll(Size(36, 36)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.bold),
                      tooltip: 'Bold',
                      onPressed: () => controller.wrapSelection('**', '**'),
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.italic),
                      tooltip: 'Italic',
                      onPressed: () => controller.wrapSelection('_', '_'),
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.strikethrough),
                      tooltip: 'Strikethrough',
                      onPressed: () => controller.wrapSelection('~~', '~~'),
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.code),
                      tooltip: 'Inline code',
                      onPressed: () => controller.wrapSelection('`', '`'),
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.heading1),
                      tooltip: 'Heading',
                      onPressed: () => controller.toggleLinePrefix('# '),
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.list),
                      tooltip: 'Unordered list',
                      onPressed: controller.toggleUnorderedList,
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.listOrdered),
                      tooltip: 'Ordered list',
                      onPressed: controller.toggleOrderedList,
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.listChecks),
                      tooltip: 'Task list',
                      onPressed: controller.toggleCheckboxList,
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
                      icon: const Icon(LucideIcons.indentIncrease),
                      tooltip: 'Indent',
                      onPressed: controller.indent,
                    ),
                    IconButton(
                      style: _tightIconButtonStyle,
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
