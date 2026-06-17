import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

// Stage 1 stub: keyboard toggle is fully functional; formatting buttons are
// disabled until Stage 2 delivers selection-aware wrap actions.
class FormattingToolbar extends StatelessWidget {
  const FormattingToolbar({
    super.key,
    required this.keyboardVisible,
    required this.onToggleKeyboard,
  });

  final bool keyboardVisible;
  final VoidCallback onToggleKeyboard;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            _StubButton(icon: LucideIcons.bold, tooltip: 'Bold'),
            _StubButton(icon: LucideIcons.italic, tooltip: 'Italic'),
            _StubButton(icon: LucideIcons.strikethrough, tooltip: 'Strikethrough'),
            _StubButton(icon: LucideIcons.list, tooltip: 'Bullet list'),
            _StubButton(icon: LucideIcons.listOrdered, tooltip: 'Numbered list'),
            _StubButton(icon: LucideIcons.listChecks, tooltip: 'Task list'),
            _StubButton(icon: LucideIcons.link, tooltip: 'Link'),
            const Spacer(),
            IconButton(
              icon: Icon(keyboardVisible
                  ? LucideIcons.keyboardOff
                  : LucideIcons.keyboard),
              tooltip: keyboardVisible ? 'Dismiss keyboard' : 'Show keyboard',
              onPressed: onToggleKeyboard,
            ),
          ],
        ),
      ),
    );
  }
}

class _StubButton extends StatelessWidget {
  const _StubButton({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: null,
    );
  }
}
