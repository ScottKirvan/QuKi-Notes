const PLACEHOLDER_IMAGE =
  "data:image/svg+xml;utf8," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">' +
      '<rect width="120" height="60" fill="#0969da"/>' +
      '<text x="60" y="34" font-size="12" fill="white" text-anchor="middle">QuKi</text>' +
      "</svg>",
  );

export const SAMPLE_DOCUMENT = `# QuKi Notes editor proof

## Try it

Move the caret in and out of the elements below. Each one hides its raw
markdown delimiters until the caret is near or inside it, then shows them
again.

### Inline elements

This is **bold text** and this is *italic text*, and this is ~~struck
through~~. Here is \`inline code\` and a [link to example.com](https://example.com).

### Nesting — rule 2

**bold containing *italic* text** must reveal as one whole span the moment
the caret enters anywhere inside it — including when the caret sits only
inside the inner *italic* part. The inner element never reveals alone.

### Block markers reveal only themselves — rule 3/4

Put the caret right after the "# " on the heading above: only the marker
shows. Move it into the heading text: the marker hides again but the text
stays styled as a heading.

### Whole-line elements — rule 4 degenerate case

![placeholder image](${PLACEHOLDER_IMAGE})

---

### Boundary inclusivity — rule 2

Put the caret immediately after the closing \`**\` of **this** run — it
should still show the delimiters. One more keystroke collapses them.
`;
