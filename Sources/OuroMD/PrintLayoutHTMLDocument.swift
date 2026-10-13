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
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static func printLayoutConfiguration(for settings: PrintLayoutSettings) -> String {
        let payload: [String: Any] = [
            "includeExternalLinkReferences": settings.includeExternalLinkReferences
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"includeExternalLinkReferences\":true}"
        }
        return json
    }

    private static func baseCSS(for settings: PrintLayoutSettings) -> String {
        let normalized = settings.normalized
        return """
        @page {
          size: auto;
          margin: \(cssLength(normalized.margins.top))pt \(cssLength(normalized.margins.right))pt \(cssLength(normalized.margins.bottom))pt \(cssLength(normalized.margins.left))pt;
        }
        html {
          -webkit-text-size-adjust: 100%;
          print-color-adjust: exact;
          -webkit-print-color-adjust: exact;
          background: #ffffff;
        }
        body {
          margin: 0;
          background: #ffffff;
          color: #111111;
          font: \(cssLength(normalized.fontSize))pt/\(cssNumber(normalized.lineSpacing)) Georgia, "Times New Roman", serif;
        }
        .markdown-body {
          color: #111111;
          max-width: none;
          margin: 0;
          overflow-wrap: break-word;
          word-break: normal;
          hanging-punctuation: first last;
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
        }
        .markdown-body p,
        .markdown-body li,
        .markdown-body blockquote,
        .markdown-body td,
        .markdown-body th {
          orphans: 3;
          widows: 3;
        }
        .markdown-body pre,
        .markdown-body code,
        .markdown-body samp,
        .markdown-body kbd {
          font-family: "SFMono-Regular", Menlo, Consolas, monospace;
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
          page-break-inside: auto;
          break-inside: auto;
        }
        .markdown-body thead {
          display: table-header-group;
        }
        .markdown-body tr,
        .markdown-body th,
        .markdown-body td {
          page-break-inside: avoid;
          break-inside: avoid;
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
