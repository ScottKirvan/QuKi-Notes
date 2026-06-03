import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/features/window/window_state_service.dart';

void main() {
  group('WindowStateService prefs round-trip', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('writeToPrefs then readFromPrefs restores exact bounds', () async {
      final prefs = await SharedPreferences.getInstance();
      const bounds = Rect.fromLTWH(100, 200, 800, 600);

      await WindowStateService.writeToPrefs(prefs, bounds);
      final result = WindowStateService.readFromPrefs(prefs);

      expect(result, equals(bounds));
    });

    test('readFromPrefs returns null on first launch (no keys)', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(WindowStateService.readFromPrefs(prefs), isNull);
    });

    test('readFromPrefs returns null when only some keys present', () async {
      SharedPreferences.setMockInitialValues({
        'window.x': 100.0,
        'window.y': 200.0,
        // width and height missing
      });
      final prefs = await SharedPreferences.getInstance();
      expect(WindowStateService.readFromPrefs(prefs), isNull);
    });
  });
}
