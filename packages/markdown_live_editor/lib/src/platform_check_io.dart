// Non-web implementation of [isMobilePlatform] — see platform_check.dart.
//
// Uses dart:io's Platform directly, preserving the exact pre-existing
// behavior (including under `flutter test`, where this reflects the real
// test-host OS, not TargetPlatform.android) on Android/iOS/Windows/Linux.

import 'dart:io' show Platform;

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
