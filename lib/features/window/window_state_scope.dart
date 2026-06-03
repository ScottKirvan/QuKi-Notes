import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'window_state_service.dart';

// Listens for window move/resize/close and persists bounds to shared_preferences.
// Mount this once at the app root on Windows + Linux.
class WindowStateScope extends StatefulWidget {
  const WindowStateScope({super.key, required this.child});

  final Widget child;

  @override
  State<WindowStateScope> createState() => _WindowStateScopeState();
}

class _WindowStateScopeState extends State<WindowStateScope>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // Use *d callbacks (fires once after the gesture ends) to avoid hammering
  // SharedPreferences on every pixel during a drag.
  @override
  void onWindowMoved() => WindowStateService.save();

  @override
  void onWindowResized() => WindowStateService.save();

  @override
  void onWindowClose() => WindowStateService.save();

  @override
  Widget build(BuildContext context) => widget.child;
}
