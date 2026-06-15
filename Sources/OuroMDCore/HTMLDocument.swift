import Foundation

/// Builds self-contained HTML documents and provides HTML-escaping helpers.
/// Used by the headless `--render` path and by HTML/PDF export.
public enum HTMLDocument {
    /// Escapes text for use in HTML element content.
    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Escapes text for use inside a double-quoted HTML attribute.
    public static func escapeAttr(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Wraps rendered body HTML in a complete, theme-styled HTML document.
    public static func wrap(body: String, css: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>
        \(baseReset)
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    public static let baseReset = """
    *,*::before,*::after{box-sizing:border-box}
    html{-webkit-text-size-adjust:100%}
    body{margin:0}
    img{max-width:100%;height:auto}
    .markdown-body{margin:0 auto;overflow-wrap:break-word;word-wrap:break-word}
    """
}
