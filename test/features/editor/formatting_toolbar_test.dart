import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:quki_notes/features/editor/editor_screen.dart';

void main() {
  group('FormattingToolbar', () {
    Future<void> pumpEditor(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: EditorScreen()),
        ),
      );
      await tester.pump();
    }

    test('toolbar button icons are defined', () {
      expect(LucideIcons.bold, isNotNull);
      expect(LucideIcons.italic, isNotNull);
      expect(LucideIcons.strikethrough, isNotNull);
      expect(LucideIcons.list, isNotNull);
      expect(LucideIcons.listOrdered, isNotNull);
      expect(LucideIcons.code, isNotNull);
      expect(LucideIcons.link, isNotNull);
    });

    testWidgets('renders all expected toolbar buttons', (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(LucideIcons.bold), findsOneWidget);
      expect(find.byIcon(LucideIcons.italic), findsOneWidget);
      expect(find.byIcon(LucideIcons.strikethrough), findsOneWidget);
      expect(find.byIcon(LucideIcons.list), findsOneWidget);
      expect(find.byIcon(LucideIcons.listOrdered), findsOneWidget);
      expect(find.byIcon(LucideIcons.code), findsOneWidget);
      expect(find.byIcon(LucideIcons.link), findsOneWidget);
    });

    testWidgets('link button shows stub snackbar', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(LucideIcons.link));
      await tester.pump();
      expect(find.text('Link formatting coming soon.'), findsOneWidget);
    });
  });
}
