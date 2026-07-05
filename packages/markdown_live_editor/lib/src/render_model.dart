import 'package:flutter/widgets.dart';

import 'md_parser.dart';

// ---------------------------------------------------------------------------
// RenderModel — builds a rendered TextSpan tree and bidirectional offset
// mappings from a parsed element list and a cursor position.
// ---------------------------------------------------------------------------

class RenderModel {
  const RenderModel._({
    required this.textSpan,
    required this.renderedLength,
    required this.sourceToRendered,
    required this.renderedToSource,
  });

  /// The rendered TextSpan to pass to TextPainter.  Contains only visible
  /// characters (delimiters of collapsed elements are absent).
  final TextSpan textSpan;

  /// Number of characters in the rendered text (= renderedToSource.length - 1).
  final int renderedLength;

  /// Maps every source offset in [0 .. source.length] to a rendered offset.
  /// Multiple source offsets may map to the same rendered offset (delimiter
  /// chars of collapsed elements all map to the boundary of their rendered
  /// content).
  final List<int> sourceToRendered;

  /// Maps every rendered offset in [0 .. renderedLength] to a source offset.
  /// Length = renderedLength + 1.
  final List<int> renderedToSource;

  int renderedForSource(int srcOff) =>
      sourceToRendered[srcOff.clamp(0, sourceToRendered.length - 1)];

  int sourceForRendered(int rndOff) =>
      renderedToSource[rndOff.clamp(0, renderedToSource.length - 1)];

  static final _empty = RenderModel._(
    textSpan: const TextSpan(text: ''),
    renderedLength: 0,
    sourceToRendered: [0],
    renderedToSource: [0],
  );

  /// Build a [RenderModel] from [source], parsed [elements], and the current
  /// [cursorOffset] (-1 when selection is invalid).
  static RenderModel build({
    required String source,
    required List<MdElement> elements,
    required int cursorOffset,
    required TextStyle baseStyle,
  }) {
    if (source.isEmpty) return _empty;

    final srcToRnd = List<int>.filled(source.length + 1, 0);
    final rndToSrc = <int>[];
    final spans = <TextSpan>[];
    final bufText = StringBuffer();
    TextStyle? bufStyle;
    var ri = 0;
    var eIdx = 0;

    void flushBuf() {
      if (bufText.isNotEmpty) {
        spans.add(TextSpan(text: bufText.toString(), style: bufStyle));
        bufText.clear();
        bufStyle = null;
      }
    }

    for (var si = 0; si < source.length; si++) {
      final char = source[si];

      // Advance eIdx past elements whose end is <= si (no longer relevant).
      while (eIdx < elements.length && elements[eIdx].end <= si) {
        eIdx++;
      }

      // Determine which element (if any) contains si.
      final MdElement? currentEl =
          (eIdx < elements.length && si >= elements[eIdx].start)
              ? elements[eIdx]
              : null;

      final revealed = currentEl != null &&
          cursorOffset >= currentEl.start &&
          cursorOffset <= currentEl.end;

      // Determine visibility and style for this character.
      bool visible;
      TextStyle charStyle;

      if (currentEl == null) {
        visible = true;
        charStyle = baseStyle;
      } else if (revealed) {
        visible = true;
        charStyle = baseStyle;
      } else {
        // Collapsed.
        if (currentEl.isDelimiter(si)) {
          visible = false;
          charStyle = baseStyle; // unused, but Dart requires initialization
        } else {
          visible = true;
          charStyle = _contentStyle(currentEl.kind, baseStyle);
        }
      }

      // Update source→rendered map (always, even for invisible chars).
      srcToRnd[si] = ri;

      if (visible) {
        // Group into a style run.
        if (charStyle != bufStyle) {
          flushBuf();
          bufStyle = charStyle;
        }
        bufText.write(char);
        rndToSrc.add(si);
        ri++;
      }
    }

    // Finalize.
    flushBuf();
    srcToRnd[source.length] = ri;
    rndToSrc.add(source.length); // end sentinel: renderedLength → source.length

    return RenderModel._(
      textSpan: TextSpan(children: spans.isEmpty ? null : spans),
      renderedLength: ri,
      sourceToRendered: srcToRnd,
      renderedToSource: rndToSrc,
    );
  }
}

// ---------------------------------------------------------------------------
// Content style helper — file-private.
// ---------------------------------------------------------------------------

TextStyle _contentStyle(MdElKind kind, TextStyle base) => switch (kind) {
      MdElKind.h1 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 2.0,
          fontWeight: FontWeight.bold,
        ),
      MdElKind.h2 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 1.5,
          fontWeight: FontWeight.bold,
        ),
      MdElKind.h3 => base.copyWith(
          fontSize: (base.fontSize ?? 16.0) * 1.25,
          fontWeight: FontWeight.bold,
        ),
      MdElKind.bold => base.copyWith(fontWeight: FontWeight.bold),
      MdElKind.italic => base.copyWith(fontStyle: FontStyle.italic),
    };
