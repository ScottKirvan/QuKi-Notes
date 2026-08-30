// Throwaway Phase 0 spike harness — see notes/dev/web_platform.md and the
// task brief in Agents/quiki-dev/CLAUDE.md ("Spike: does markdown_live_editor
// work on iOS Safari, and is Web Share reachable at all?").
//
// This is deliberately NOT the QuKi-Notes app. It imports markdown_live_editor
// directly and answers exactly two questions:
//   1. Does the editor render and accept real keyboard/touch input on iOS
//      Safari (typing, IME composition, selection, custom-painted markers)?
//   2. Is navigator.share() reachable at all from iOS Safari / an installed
//      PWA?
//
// Nothing here is meant to be kept — no storage, no transports, no design
// system. Nothing from lib/ (the main app) is imported.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

import 'web_share.dart';

void main() {
  // Diagnostic only, not part of the "real" spike UI: markdown_live_editor's
  // internal `_isMobile` gate (guards tap/drag selection — handles, toolbar)
  // is implemented as `Platform.isAndroid || Platform.isIOS`
  // (quiki_editor.dart). `dart:io` compiles for web (the Dart web SDK ships
  // a stub), but it's an open question whether *calling* `Platform.*` at
  // runtime throws in a browser — if it does, every tap/drag selection
  // attempt crashes with an uncaught exception. Checked once at startup and
  // surfaced in the UI (see _platformCheckResult) rather than assumed.
  try {
    _platformCheckResult =
        'dart:io Platform.isAndroid/.isIOS read OK '
        '(isAndroid=${Platform.isAndroid}, isIOS=${Platform.isIOS}) — '
        'this is the exact call markdown_live_editor\'s selection gate makes.';
  } catch (e) {
    _platformCheckResult =
        'dart:io Platform.* THREW at runtime: $e — this is the exact call '
        'markdown_live_editor\'s tap/drag-selection gate (_isMobile) makes, '
        'so selection is expected to crash until this is patched.';
  }
  // Also printed to the console (visible via `flutter run`'s terminal
  // output, or the browser devtools console) since this diagnostic matters
  // before the widget tree even paints.
  // ignore: avoid_print
  print('[spike] $_platformCheckResult');
  runApp(const SpikeApp());
}

late final String _platformCheckResult;

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'markdown_live_editor web spike',
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const SpikeHomePage(),
    );
  }
}

// Seed content exercises every custom-paint path the brief calls out:
// a heading, bold/italic, an unordered list, an ordered list, a checkbox
// (checked + unchecked), a blockquote, and a link — so a single glance at
// the rendered page tells you whether the paint layer works at all.
const String _seedMarkdown = '''
# markdown_live_editor web spike

Type here to test **bold**, *italic*, and IME composition (try a non-Latin
input method if you have one — Pinyin, Kana, etc).

- an unordered list item
- another item

1. an ordered list item
2. another item

- [ ] an unchecked checkbox
- [x] a checked checkbox

> a blockquote, to confirm the stripe paints

A [link](https://example.com) to confirm inline link rendering.
''';

class SpikeHomePage extends StatefulWidget {
  const SpikeHomePage({super.key});

  @override
  State<SpikeHomePage> createState() => _SpikeHomePageState();
}

class _SpikeHomePageState extends State<SpikeHomePage> {
  final MarkdownEditorController _controller = MarkdownEditorController();
  String _lastChanged = '(no changes yet)';
  String _shareStatus = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('markdown_live_editor — web spike'),
        actions: [
          // A single, isolated tap-to-share action, kept as short as
          // possible from tap to navigator.share() per web_platform.md §5 —
          // no unrelated async work runs before the call.
          IconButton(
            tooltip: 'Share via Web Share API',
            icon: const Icon(Icons.ios_share),
            onPressed: _onShareTapped,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.indigo.shade900,
            padding: const EdgeInsets.all(8),
            child: Text(
              _platformCheckResult,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          if (_shareStatus.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.black87,
              padding: const EdgeInsets.all(8),
              child: Text(
                _shareStatus,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          Expanded(
            child: MarkdownEditor(
              initialValue: _seedMarkdown,
              controller: _controller,
              autofocus: true,
              config: const MarkdownEditorConfig(
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (value) {
                setState(
                  () => _lastChanged = 'onChanged fired, ${value.length} chars',
                );
              },
              onLinkTap: (url) {
                setState(() => _shareStatus = 'onLinkTap: $url');
              },
            ),
          ),
          FormattingToolbar(controller: _controller),
          Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(_lastChanged, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Future<void> _onShareTapped() async {
    // Deliberately no other async work before this — see web_platform.md §5
    // on keeping the tap-to-share() call chain short, echoing this project's
    // own Android share-sheet lesson about async gaps before a native share
    // call.
    final result = await shareText(
      title: 'QuKi-Notes web spike',
      text: 'Shared from the markdown_live_editor web spike harness.',
    );
    if (!mounted) return;
    setState(() => _shareStatus = result);
  }
}
