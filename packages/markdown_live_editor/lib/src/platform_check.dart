// Conditional-import seam so `_isMobile` (quiki_editor.dart) works on web
// without changing behavior anywhere else.
//
// Same idiom Flutter's own foundation/platform.dart uses to pick between
// dart:io and a web-safe implementation: `dart.library.js_interop` is only
// available when compiling for web, so non-web platforms (including the
// `flutter test` host) get the dart:io version unchanged.
export 'platform_check_io.dart'
    if (dart.library.js_interop) 'platform_check_web.dart';
