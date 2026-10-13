import Foundation
import OuroMDCore

enum PrintLayoutHTMLDocument {
    static func wrap(body: String, title: String, settings: PrintLayoutSettings, script: String) -> String {
        let normalized = settings.normalized
        let config = printLayoutConfiguration(for: normalized)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTMLDocument.escape(title))</title>
        <style>
        \(baseCSS(for: normalized))
        </style>
        <script>
        window.__ouroPrintLayoutConfig = \(config);
        </script>
        <script>
        \(script)
        </script>
        </head>
        <body>
        <div class="ouro-print-viewport">
          <div class="ouro-print-root">
            <article class="markdown-body ouro-print-pages">
            \(body)
            </article>
          </div>
        </div>
        </body>
        </html>
        """
    }

    private static func printLayoutConfiguration(for settings: PrintLayoutSettings) -> String {
        let payload: [String: Any] = [
            "pageWidth": 612.0,
            "pageHeight": 792.0,
            "pageContentWidth": contentWidth(for: settings),
            "pageContentHeight": contentHeight(for: settings),
            "marginTop": settings.margins.top,
            "marginRight": settings.margins.right,
            "marginBottom": settings.margins.bottom,
            "marginLeft": settings.margins.left,
            "pageGap": 24.0,
            "includeExternalLinkReferences": settings.includeExternalLinkReferences
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"includeExternalLinkReferences\":false}"
        }
        return json
    }

    private static func baseCSS(for settings: PrintLayoutSettings) -> String {
        let normalized = settings.normalized
        let contentWidth = contentWidth(for: normalized)
        let contentHeight = contentHeight(for: normalized)
        return """
        html {
          -webkit-text-size-adjust: 100%;
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
          background: #ffffff;
        }
        :root {
          --ouro-page-width: 612pt;
          --ouro-page-height: 792pt;
          --ouro-page-content-width: \(cssLength(contentWidth))pt;
          --ouro-page-content-height: \(cssLength(contentHeight))pt;
          --ouro-page-gap: 24pt;
          --ouro-active-page: 0;
        }
        body {
          margin: 0;
          background: #ffffff;
          color: #111111;
          font: \(cssLength(normalized.fontSize))pt/\(cssNumber(normalized.lineSpacing)) Georgia, "Times New Roman", serif;
        }
        .ouro-print-viewport {
          width: var(--ouro-page-width);
          height: var(--ouro-page-height);
          overflow: hidden;
          background: #ffffff;
        }
        .ouro-print-root {
          width: max-content;
          background: #ffffff;
          transform: translateX(calc(-1 * var(--ouro-active-page-offset, 0px)));
          transform-origin: top left;
        }
        .markdown-body {
          box-sizing: border-box;
          color: #111111;
          width: var(--ouro-page-width);
          max-width: var(--ouro-page-width);
          margin: 0;
          padding: \(cssLength(normalized.margins.top))pt \(cssLength(normalized.margins.right))pt \(cssLength(normalized.margins.bottom))pt \(cssLength(normalized.margins.left))pt;
          overflow-wrap: break-word;
          word-break: normal;
          hanging-punctuation: first last;
          column-width: var(--ouro-page-width);
          column-gap: var(--ouro-page-gap);
          column-fill: auto;
          height: var(--ouro-page-height);
        }
        .markdown-body > :first-child { margin-top: 0; }
        .markdown-body > :last-child { margin-bottom: 0; }
        .markdown-body h1,
        .markdown-body h2,
        .markdown-body h3,
        .markdown-body h4,
        .markdown-body h5,
        .markdown-body h6 {
          color: #000000;
          break-after: avoid-page;
          break-inside: avoid;
          page-break-after: avoid;
          -webkit-column-break-inside: avoid;
        }
        .markdown-body p,
        .markdown-body li,
        .markdown-body blockquote,
        .markdown-body td,
        .markdown-body th {
          orphans: 3;
          widows: 3;
        }
        .markdown-body p,
        .markdown-body blockquote,
        .markdown-body pre,
        .markdown-body table,
        .markdown-body .ouro-print-keep-together,
        .markdown-body img,
        .markdown-body svg,
        .markdown-body figure,
        .markdown-body ul,
        .markdown-body ol,
        .markdown-body li,
        .markdown-body tr,
        .markdown-body thead,
        .markdown-body tbody,
        .markdown-body section {
          break-inside: avoid;
          page-break-inside: avoid;
          -webkit-column-break-inside: avoid;
        }
        .markdown-body .ouro-print-keep-together {
          display: block;
        }
        .markdown-body pre,
        .markdown-body code,
        .markdown-body samp,
        .markdown-body kbd {
          font-family: "SFMono-Regular", Menlo, Consolas, monospace;
        }
        .markdown-body .katex {
          white-space: nowrap;
        }
        .markdown-body .katex-display {
          display: block;
          text-align: center;
          margin: 1em 0;
        }
        .markdown-body .katex .base,
        .markdown-body .katex .mord,
        .markdown-body .katex .mrel,
        .markdown-body .katex .mspace {
          display: inline-block;
        }
        .markdown-body pre {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
          background: #f6f8fa;
          border: 1px solid #d0d7de;
          border-radius: 6px;
          padding: 0.9em;
        }
        .markdown-body code {
          overflow-wrap: anywhere;
          word-break: break-word;
        }
        .markdown-body img,
        .markdown-body svg,
        .markdown-body video,
        .markdown-body canvas {
          max-width: 100%;
          height: auto;
          page-break-inside: avoid;
          break-inside: avoid;
        }
        .markdown-body table {
          width: 100%;
          max-width: 100%;
          border-collapse: collapse;
          table-layout: fixed;
          margin: 1.1em 0;
        }
        .markdown-body thead {
          display: table-header-group;
        }
        .markdown-body tr,
        .markdown-body th,
        .markdown-body td {
          vertical-align: top;
        }
        .markdown-body th,
        .markdown-body td {
          border: 1px solid #d0d7de;
          padding: 0.45em 0.6em;
          overflow-wrap: anywhere;
          word-break: break-word;
          white-space: normal;
        }
        .markdown-body blockquote {
          border-left: 3px solid #8c959f;
          color: #333333;
          margin: 1em 0;
          padding: 0.2em 1em;
        }
        .markdown-body hr {
          border: 0;
          border-top: 1px solid #d0d7de;
          margin: 1.4em 0;
        }
        .markdown-body a,
        .markdown-body a:visited {
          color: #111111;
          text-decoration: underline;
          text-underline-offset: 0.12em;
        }
        .markdown-body .footnotes {
          margin-top: 1.8em;
          break-inside: avoid;
        }
        .ouro-print-external-links {
          margin-top: 1.8em;
          break-inside: avoid;
        }
        .ouro-print-reference-marker {
          font-size: 0.72em;
          line-height: 1;
          vertical-align: super;
          margin-left: 0.1em;
          white-space: nowrap;
        }
        .ouro-print-reference-marker a,
        .ouro-print-reference-marker a:visited {
          text-decoration: none;
        }
        .ouro-print-reference-url {
          overflow-wrap: anywhere;
          word-break: break-word;
        }
        .ouro-print-reference-url code {
          font-size: 0.92em;
        }
        .vditor-toolbar,
        .vditor-preview__action,
        #ouro-change-marks,
        #ouro-next-change,
        .ouro-change-mark,
        .ouro-change-flash,
        .ouro-callout-editing,
        .vditor-ir__marker,
        .vditor-toolbar,
        [data-ouro-change],
        [data-ouro-change-kind] {
          display: none !important;
        }
        """
    }

    private static func contentWidth(for settings: PrintLayoutSettings) -> Double {
        612 - settings.margins.left - settings.margins.right
    }

    private static func contentHeight(for settings: PrintLayoutSettings) -> Double {
        792 - settings.margins.top - settings.margins.bottom
    }

    private static func cssLength(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func cssNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
