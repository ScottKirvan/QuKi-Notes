import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quki_notes/app.dart';

void main() {
  testWidgets('app smoke test — EditorScreen renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QuKiNotesApp()));
    await tester.pump();
    expect(find.byType(QuKiNotesApp), findsOneWidget);
  });
}
