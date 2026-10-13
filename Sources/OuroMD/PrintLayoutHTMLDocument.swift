import AppKit
import Foundation
import OuroMDCore

enum PrintLayoutHTMLDocument {
    static func wrap(body: String, title: String, settings: PrintLayoutSettings, script: String, paperSize: NSSize = NSSize(width: 612, height: 792)) -> String {
        let normalized = settings.normalized
        let config = printLayoutConfiguration(for: normalized, paperSize: paperSize)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTMLDocument.escape(title))</title>
        <style>
        \(baseCSS(for: normalized, paperSize: paperSize))
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
            <div class="ouro-print-content-frame">
              <article class="markdown-body ouro-print-pages">
              \(body)
              </article>
            </div>
          </div>
        </div>
        </body>
        </html>
        """
    }

    private static func printLayoutConfiguration(for settings: PrintLayoutSettings, paperSize: NSSize) -> String {
        let payload: [String: Any] = [
            "pageWidth": paperSize.width,
            "pageHeight": paperSize.height,
            "pageContentWidth": paperSize.width - settings.margins.left - settings.margins.right,
            "pageContentHeight": paperSize.height - settings.margins.top - settings.margins.bottom,
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

    private static func baseCSS(for settings: PrintLayoutSettings, paperSize: NSSize) -> String {
        let normalized = settings.normalized
        let contentWidth = paperSize.width - normalized.margins.left - normalized.margins.right
        let contentHeight = paperSize.height - normalized.margins.top - normalized.margins.bottom
        return """
        html {
          -webkit-text-size-adjust: 100%;
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
          background: #ffffff;
        }
        :root {
          --ouro-page-width: \(cssLength(paperSize.width))px;
          --ouro-page-height: \(cssLength(paperSize.height))px;
          --ouro-page-content-width: \(cssLength(contentWidth))px;
          --ouro-page-content-height: \(cssLength(contentHeight))px;
          --ouro-page-gap: 24px;
          --ouro-active-page: 0;
        }
        body {
          margin: 0;
          background: #ffffff;
          color: #111111;
          font: \(cssLength(normalized.fontSize))px/\(cssNumber(normalized.lineSpacing)) Georgia, "Times New Roman", serif;
        }
        .ouro-print-viewport {
          width: var(--ouro-page-width);
          height: var(--ouro-page-height);
          overflow: hidden;
          background: #ffffff;
        }
        .ouro-print-root {
          position: relative;
          width: var(--ouro-page-width);
          height: var(--ouro-page-height);
          background: #ffffff;
        }
        .ouro-print-content-frame {
          position: absolute;
          left: \(cssLength(normalized.margins.left))px;
          top: \(cssLength(normalized.margins.top))px;
          width: var(--ouro-page-content-width);
          height: var(--ouro-page-content-height);
          overflow: hidden;
        }
        .markdown-body {
          box-sizing: border-box;
          color: #111111;
          width: var(--ouro-page-content-width);
          max-width: var(--ouro-page-content-width);
          margin: 0;
          transform: translateX(calc(-1 * var(--ouro-active-page-offset, 0px)));
          transform-origin: top left;
          overflow-wrap: break-word;
          word-break: normal;
          hanging-punctuation: first last;
          column-width: var(--ouro-page-content-width);
          column-gap: var(--ouro-page-gap);
          column-fill: auto;
          height: var(--ouro-page-content-height);
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

    private static func cssLength(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func cssNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
