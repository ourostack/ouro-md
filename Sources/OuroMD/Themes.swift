import Foundation

/// A visual theme: standalone-document CSS (for `--render` / export) and
/// in-editor CSS (scoped to the web editor's content), plus the web editor's
/// light/dark UI mode.
struct Theme: Identifiable {
    let id: String
    let displayName: String
    /// Web-editor UI mode: "classic" (light) or "dark".
    let uiMode: String
    /// CSS for standalone HTML documents (targets `.markdown-body`).
    let css: String
    /// CSS injected into the live editor (targets the editor's content nodes).
    let editorCSS: String
}

/// Color + type tokens for a built-in theme. Both stylesheets are generated
/// from these so the standalone export and the live editor stay in sync.
private struct Palette {
    let id: String
    let displayName: String
    let uiMode: String
    let bg: String
    let surface: String
    let fg: String
    let faint: String
    let accent: String
    let border: String
    let quoteBar: String
    let selection: String
    let font: String
    let mono: String
    let maxWidth: String
    let fontSize: String
}

private enum Fonts {
    static let sans = #"-apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif"#
    static let serif = #""New York", "Iowan Old Style", Palatino, Georgia, "Times New Roman", serif"#
    static let mono = #"ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Monaco, Consolas, monospace"#
}

/// Loads and serves built-in + user themes.
final class ThemeStore {
    static let shared = ThemeStore()

    let themes: [Theme]

    private init() {
        var all = ThemeStore.builtIns()
        all.append(contentsOf: ThemeStore.userThemes())
        themes = all
    }

    var defaultTheme: Theme {
        themes.first(where: { $0.id == "quartz" }) ?? themes[0]
    }

    func theme(id: String) -> Theme {
        themes.first(where: { $0.id == id }) ?? defaultTheme
    }

    static var userThemesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ouro-md/Themes", isDirectory: true)
    }

    // MARK: - Built-ins

    private static func builtIns() -> [Theme] {
        let palettes = [
            Palette(id: "quartz", displayName: "Quartz", uiMode: "classic",
                    bg: "#fbfbfa", surface: "#f0f0ee", fg: "#2b2b2b", faint: "#8a8a86",
                    accent: "#2f6fdb", border: "#e7e7e2", quoteBar: "#d9d9d2",
                    selection: "rgba(47,111,219,0.15)", font: Fonts.sans, mono: Fonts.mono,
                    maxWidth: "760px", fontSize: "17px"),
            Palette(id: "graphite", displayName: "Graphite", uiMode: "dark",
                    bg: "#1b1c1d", surface: "#262829", fg: "#d8d9da", faint: "#8b8d8f",
                    accent: "#6aa3ff", border: "#313335", quoteBar: "#3c3f42",
                    selection: "rgba(106,163,255,0.22)", font: Fonts.sans, mono: Fonts.mono,
                    maxWidth: "760px", fontSize: "17px"),
            Palette(id: "manuscript", displayName: "Manuscript", uiMode: "classic",
                    bg: "#f4ecd8", surface: "#ece1c6", fg: "#4a3f2f", faint: "#8c7a5c",
                    accent: "#9a5b34", border: "#ddd0b0", quoteBar: "#c9b88f",
                    selection: "rgba(154,91,52,0.16)", font: Fonts.serif, mono: Fonts.mono,
                    maxWidth: "700px", fontSize: "18px"),
            Palette(id: "newsprint", displayName: "Newsprint", uiMode: "classic",
                    bg: "#ffffff", surface: "#f3f3f3", fg: "#1a1a1a", faint: "#6b6b6b",
                    accent: "#111111", border: "#e3e3e3", quoteBar: "#cfcfcf",
                    selection: "rgba(0,0,0,0.10)", font: Fonts.serif, mono: Fonts.mono,
                    maxWidth: "720px", fontSize: "18px")
        ]
        return palettes.map {
            Theme(id: $0.id, displayName: $0.displayName, uiMode: $0.uiMode,
                  css: readerCSS($0), editorCSS: editorCSS($0))
        }
    }

    // MARK: - User themes

    private static func userThemes() -> [Theme] {
        let dir = userThemesDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "css" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> Theme? in
                guard let css = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let id = url.deletingPathExtension().lastPathComponent
                let name = id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
                let uiMode = id.lowercased().contains("dark") ? "dark" : "classic"
                return Theme(id: id, displayName: name, uiMode: uiMode, css: css, editorCSS: css)
            }
    }
}

// MARK: - Stylesheet generation

private func readerCSS(_ p: Palette) -> String {
    """
    :root{color-scheme:\(p.uiMode == "dark" ? "dark" : "light");}
    body{background:\(p.bg);color:\(p.fg);font-family:\(p.font);font-size:\(p.fontSize);line-height:1.75;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;}
    ::selection{background:\(p.selection);}
    .markdown-body{max-width:\(p.maxWidth);padding:64px 40px 120px;}
    .markdown-body>:first-child{margin-top:0;}
    h1,h2,h3,h4,h5,h6{font-weight:600;line-height:1.3;margin:1.8em 0 .6em;letter-spacing:-.01em;}
    h1{font-size:2.1em;letter-spacing:-.02em;}
    h2{font-size:1.6em;}
    h3{font-size:1.28em;}
    h4{font-size:1.06em;}
    h5,h6{font-size:.95em;color:\(p.faint);}
    p{margin:0 0 1.15em;}
    a{color:\(p.accent);text-decoration:none;border-bottom:1px solid transparent;transition:border-color .15s;}
    a:hover{border-bottom-color:\(p.accent);}
    strong{font-weight:600;}
    em{font-style:italic;}
    del{color:\(p.faint);}
    code{font-family:\(p.mono);font-size:.86em;background:\(p.surface);padding:.16em .42em;border-radius:6px;}
    pre{background:\(p.surface);padding:16px 18px;border-radius:12px;overflow:auto;line-height:1.55;margin:1.3em 0;}
    pre code{background:none;padding:0;font-size:.86em;}
    blockquote{margin:1.3em 0;padding:.2em 0 .2em 1.1em;border-left:3px solid \(p.quoteBar);color:\(p.faint);}
    blockquote p{margin:.4em 0;}
    hr{border:none;height:1px;background:\(p.border);margin:2.4em 0;}
    ul,ol{margin:0 0 1.15em;padding-left:1.5em;}
    li{margin:.35em 0;}
    li::marker{color:\(p.faint);}
    .task-list-item{list-style:none;}
    .task-list-item input{margin:0 .55em 0 -1.5em;vertical-align:middle;}
    table{border-collapse:collapse;width:100%;margin:1.4em 0;font-size:.95em;}
    th,td{border-bottom:1px solid \(p.border);padding:9px 14px;text-align:left;}
    thead th{border-bottom:2px solid \(p.quoteBar);font-weight:600;}
    tbody tr:hover{background:\(p.surface);}
    img{max-width:100%;height:auto;border-radius:10px;display:block;margin:1.3em auto;}
    """
}

private func editorCSS(_ p: Palette) -> String {
    """
    html,body{background:\(p.bg);margin:0;height:100%;}
    .vditor{border:none!important;background:\(p.bg)!important;height:100vh;}
    .vditor-toolbar{display:none!important;}
    .vditor-content{background:\(p.bg)!important;min-height:0;}
    .vditor-reset{color:\(p.fg)!important;font-family:\(p.font)!important;font-size:\(p.fontSize)!important;line-height:1.75;max-width:\(p.maxWidth);margin:0 auto;padding:64px 44px 180px!important;-webkit-font-smoothing:antialiased;caret-color:\(p.accent);}
    .vditor-reset::selection,.vditor-reset *::selection{background:\(p.selection);}
    .vditor-reset h1,.vditor-reset h2,.vditor-reset h3,.vditor-reset h4,.vditor-reset h5,.vditor-reset h6{font-weight:600;line-height:1.3;letter-spacing:-.01em;border:none;padding:0;}
    .vditor-reset h1{font-size:2.1em;letter-spacing:-.02em;}
    .vditor-reset h2{font-size:1.6em;}
    .vditor-reset h3{font-size:1.28em;}
    .vditor-reset h4{font-size:1.06em;}
    .vditor-reset a{color:\(p.accent);}
    .vditor-reset strong{font-weight:600;}
    .vditor-reset code:not(.hljs):not([class*="vditor-ir__marker"]){font-family:\(p.mono);background:\(p.surface);padding:.16em .42em;border-radius:6px;font-size:.86em;}
    .vditor-reset pre,.vditor-reset pre.hljs,.vditor-reset pre>code{background:\(p.surface)!important;border-radius:12px;}
    .vditor-reset blockquote{border-left:3px solid \(p.quoteBar);color:\(p.faint);padding-left:1.1em;}
    .vditor-reset hr{background:\(p.border);height:1px;border:none;}
    .vditor-reset table td,.vditor-reset table th{border-bottom:1px solid \(p.border);}
    .vditor-reset thead th{border-bottom:2px solid \(p.quoteBar);}
    .vditor-reset img{border-radius:10px;}
    .vditor-ir__marker,.vditor-ir__marker--heading,.vditor-ir__marker--bi,.vditor-ir__marker--link,.vditor-sv__marker{color:\(p.faint)!important;opacity:.55;}
    .vditor-outline{background:\(p.surface)!important;border-right:1px solid \(p.border)!important;}
    .vditor-outline__title{color:\(p.faint)!important;}
    .vditor-outline li>span:hover{background:\(p.bg)!important;}
    .vditor-counter{color:\(p.faint)!important;background:transparent!important;border:none!important;}
    .vditor-resize{display:none!important;}
    """
}
