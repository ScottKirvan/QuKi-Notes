// Web implementation of [isMobilePlatform] — see platform_check.dart.
//
// dart:io compiles for web (the Dart web SDK ships a stub) but *calling*
// Platform.isAndroid/.isIOS at runtime throws UnsupportedError — confirmed
// via `flutter run -d chrome` during the web spike
// (notes/dev/web_platform.md Phase 0): it crashed the very first widget
// build, before any user interaction, because the selection-handle
// overlay's AnimatedBuilder reads _isMobile unconditionally.
//
// defaultTargetPlatform is web-safe and, per Flutter's own foundation docs,
// resolves to the actual browser platform (TargetPlatform.iOS on real iOS
// Safari) — exactly what _isMobile needs on web.
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

bool get isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;
