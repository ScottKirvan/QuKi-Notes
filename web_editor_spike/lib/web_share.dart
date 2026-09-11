// navigator.share() / navigator.canShare() interop for the web spike.
//
// Uses dart:js_interop + package:web — the current non-deprecated approach —
// never dart:html, which is being phased out. See web_platform.md §5: this
// is the mechanism the whole "share-out" goal of the eventual feature
// depends on, and it needs a real on-device answer, not an assumption.

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Attempts `navigator.share()` with the given [title]/[text], gated by
/// `navigator.canShare()` first per web_platform.md §5's guidance not to
/// assume Web Share "just works." Returns a short human-readable status
/// string describing exactly what happened, for on-screen display — there's
/// no console visible on an iPhone, so the result has to show up in the UI
/// itself.
Future<String> shareText({required String title, required String text}) async {
  final navigator = web.window.navigator;
  final data = web.ShareData(title: title, text: text);

  // Some browsers (e.g. desktop Firefox) have no `canShare`/`share` at all.
  // Calling an undefined JS member throws rather than returning null, so
  // feature-detection happens via try/catch instead of a property check —
  // simpler and doesn't depend on a specific js_interop helper API.
  bool? canShare;
  try {
    canShare = navigator.canShare(data);
  } catch (e) {
    return 'navigator.canShare is not available in this browser: $e';
  }
  if (!canShare) {
    return 'navigator.canShare() returned false for this payload — share not offered.';
  }

  try {
    await navigator.share(data).toDart;
    return 'navigator.share() resolved successfully.';
  } catch (e) {
    // A user dismissing the native share sheet also rejects the promise
    // (AbortError) — that is expected, not a bug, so it's reported plainly
    // rather than as an unexpected failure.
    return 'navigator.share() rejected: $e';
  }
}
