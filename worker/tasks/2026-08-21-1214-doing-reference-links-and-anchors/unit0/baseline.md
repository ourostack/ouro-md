# Unit 0 baseline

- Source build completed from `c6d3bca`.
- The strict canonical fixture round-trips byte-for-byte.
- The rich fixture exposes known vendored Lute normalizations: collapsed reference syntax becomes shortcut syntax, the optional definition title is dropped, and the blank line between the footnote definition and link-reference definitions becomes four spaces.
- Lute IR emits resolved references as `span[data-type="link-ref"]` without an `href`; unresolved references remain plain paragraph text.
- Lute standalone HTML resolves full, collapsed, shortcut, local, and fragment reference destinations.
- Heading HTML from the app-facing Lute path is mode-dependent and does not use the standalone `MarkdownRenderer` slug contract.
- Same-document fragment handling remains unimplemented in the native coordinator and local Markdown fragments are discarded by `DocumentLinkResolver`.
