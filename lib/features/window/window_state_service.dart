import 'dart:ui' show Offset, Rect, Size;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowStateService {
  static const _kX = 'window.x';
  static const _kY = 'window.y';
  static const _kWidth = 'window.width';
  static const _kHeight = 'window.height';

  // Null when any key is absent (first launch → let OS place the window).
  static Rect? readFromPrefs(SharedPreferences prefs) {
    final x = prefs.getDouble(_kX);
    final y = prefs.getDouble(_kY);
    final w = prefs.getDouble(_kWidth);
    final h = prefs.getDouble(_kHeight);
    if (x == null || y == null || w == null || h == null) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  static Future<void> writeToPrefs(
    SharedPreferences prefs,
    Rect bounds,
  ) async {
    await prefs.setDouble(_kX, bounds.left);
    await prefs.setDouble(_kY, bounds.top);
    await prefs.setDouble(_kWidth, bounds.width);
    await prefs.setDouble(_kHeight, bounds.height);
  }

  // Called at launch (after windowManager.ensureInitialized()).
  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final bounds = readFromPrefs(prefs);
    if (bounds == null) return;
    await windowManager.setSize(Size(bounds.width, bounds.height));
    await windowManager.setPosition(Offset(bounds.left, bounds.top));
  }

  // Called by WindowStateScope listeners.
  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final bounds = await windowManager.getBounds();
    await writeToPrefs(prefs, bounds);
  }
}
