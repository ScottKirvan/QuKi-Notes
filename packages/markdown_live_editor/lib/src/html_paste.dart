import 'package:html/dom.dart' as dom;
import 'package:html2md/html2md.dart' as html2md;
import 'package:quill_native_bridge/quill_native_bridge.dart';

// ---------------------------------------------------------------------------
// Clipboard HTML reading (ADR-35).
//
// Kept separate from the buffer-update logic in quiki_editor.dart so that
// file's paste code stays focused on selection/buffer mechanics.
// ---------------------------------------------------------------------------

/// Reads the clipboard's HTML representation, if any is present.
///
/// Returns null when no HTML representation exists on the clipboard, or when
/// no system clipboard reader is available at all on this platform. Callers
/// fall back to the plain-text clipboard representation in either case.
typedef ClipboardHtmlReader = Future<String?> Function();

/// Real implementation, backed by `quill_native_bridge`.
///
/// Overridable per-call site via a [ClipboardHtmlReader] parameter — see
/// `QuikiEditorState.debugClipboardHtmlReader` — because quill_native_bridge's
/// native plugin channel is not available under `flutter test`, unlike
/// `Clipboard.getData`, which Flutter lets tests mock via a fake
/// `SystemChannels.platform` handler.
Future<String?> readClipboardHtml() => QuillNativeBridge().getClipboardHtml();

// ---------------------------------------------------------------------------
// HTML -> GFM markdown conversion.
// ---------------------------------------------------------------------------

/// Custom html2md rule: converts a `<li>` containing a checkbox `<input>`
/// (a GFM task-list item) to this app's exact checkbox marker syntax,
/// `- [ ] ` / `- [x] ` (6 literal characters, no extra padding).
///
/// html2md has no built-in concept of task lists — an `<input>` contributes
/// no text content on its own (it is a void, non-block element), so without
/// this rule the checkbox would simply vanish, leaving only the item's label
/// text. This rule also must not reuse html2md's own listItem padding (marker
/// + 3 spaces, e.g. `'-   '`) — [MdParser] only recognizes the exact 6-char
/// prefix `'- [ ] '` / `'- [x] '` at the start of a line; anything wider
/// falls through to plain unordered-list handling and the checkbox syntax
/// renders as literal bracket text instead of a checkbox glyph.
final html2md.Rule _taskListItemRule = html2md.Rule(
  'quikiTaskListItem',
  filterFn: (node) {
    if (node.nodeName != 'li') return false;
    return _checkboxInput(node) != null;
  },
  replacement: (content, node) {
    final checkbox = _checkboxInput(node)!;
    final checked = checkbox.attributes.containsKey('checked');
    final text = content.trim();
    // Mirror html2md's own listItem postfix rule (rules.dart): separate
    // consecutive <li> siblings with a newline. _join() (converter.dart)
    // only inserts a separator when one side already ends/starts with a
    // newline, so without this, two adjacent checkbox items would be
    // concatenated onto a single source line.
    final needsNewline = node.nextSibling != null && !text.endsWith('\n');
    return '${checked ? '- [x] ' : '- [ ] '}$text${needsNewline ? '\n' : ''}';
  },
);

dom.Element? _checkboxInput(html2md.Node li) =>
    li.asElement()?.querySelector('input[type="checkbox"]');

// html2md's custom-rule list (Rule.addRules in rules.dart) is process-global
// static state with no de-duplication — registering the same rule on every
// paste would accumulate duplicate entries for the lifetime of the process.
// Harmless functionally (Rule.findRule takes the first match), but register
// at most once regardless.
bool _taskListRuleRegistered = false;

/// Converts [html] to GFM markdown, tuned so the syntax it produces matches
/// what this app's `MdParser` recognizes (ADR-35):
/// - headings as ATX (`# `) — html2md defaults h1/h2 to setext underlines,
///   which MdParser has no support for.
/// - code blocks as fenced (` ``` `) — html2md defaults to 4-space indented
///   code blocks, which MdParser has no support for.
/// - `*` for emphasis delimiters instead of html2md's default `_` — avoids
///   CommonMark's intraword-underscore restriction, which MdParser also
///   enforces, producing spurious literal underscores for some inputs.
///
/// No other structure needs tuning: html2md's default output for bold,
/// strikethrough, inline code, links, images, blockquotes, and horizontal
/// rules already matches syntax MdParser recognizes. Tables and fenced code
/// have no special *rendering* in MdParser yet (#245, #244) but html2md's
/// output for both stays fully-structured, legible GFM markdown either way —
/// nothing is stripped or degraded to plain prose (ADR-35).
String convertHtmlToMarkdown(String html) {
  final rules = _taskListRuleRegistered ? null : [_taskListItemRule];
  final markdown = html2md.convert(
    html,
    styleOptions: const {
      'headingStyle': 'atx',
      'codeBlockStyle': 'fenced',
      'emDelimiter': '*',
    },
    rules: rules,
  );
  _taskListRuleRegistered = true;
  return markdown;
}
