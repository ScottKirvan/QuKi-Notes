import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:quki_notes/features/settings/help_dialog.dart';

Widget _buildHarness() => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showHelpDialog(context),
              child: const Text('Open help'),
            ),
          ),
        ),
      ),
    );

Future<void> cleanup(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
}

void main() {
  group('HelpDialog — version copy', () {
    testWidgets(
        'tapping the version text copies "v<version>" to the clipboard '
        'and shows a confirming snackbar', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'QuKi Notes',
        packageName: 'com.example.quki_notes',
        version: '0.23.0',
        buildNumber: '1',
        buildSignature: '',
      );

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(_buildHarness());
      await tester.tap(find.text('Open help'));
      await tester.pumpAndSettle();

      expect(find.text('v0.23.0'), findsOneWidget);

      await tester.tap(find.text('v0.23.0'));
      await tester.pump();

      final setDataCall = calls.singleWhere(
        (c) => c.method == 'Clipboard.setData',
      );
      expect(setDataCall.arguments, {'text': 'v0.23.0'});

      expect(find.text('Copied to clipboard.'), findsOneWidget);
      await cleanup(tester);
    });
  });
}
