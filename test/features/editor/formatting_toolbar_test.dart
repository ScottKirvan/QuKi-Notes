import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(Icons.format_bold, isNotNull);
      expect(Icons.format_italic, isNotNull);
      expect(Icons.format_strikethrough, isNotNull);
      expect(Icons.format_list_bulleted, isNotNull);
      expect(Icons.format_list_numbered, isNotNull);
      expect(Icons.code, isNotNull);
      expect(Icons.link, isNotNull);
    });

    testWidgets('renders all expected toolbar buttons', (tester) async {
      await pumpEditor(tester);
      expect(find.byIcon(Icons.format_bold), findsOneWidget);
      expect(find.byIcon(Icons.format_italic), findsOneWidget);
      expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);
      expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget);
      expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('link button shows stub snackbar', (tester) async {
      await pumpEditor(tester);
      await tester.tap(find.byIcon(Icons.link));
      await tester.pump();
      expect(find.text('Link formatting coming soon.'), findsOneWidget);
    });
  });
}
