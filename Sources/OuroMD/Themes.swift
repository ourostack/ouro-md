import Foundation

/// A visual theme: standalone-document CSS (for `--render` / export) and
/// in-editor CSS (scoped to the web editor's content), plus the web editor's
/// light/dark UI mode.
struct Theme: Identifiable {
    let id: String
    let displayName: String
    /// Web-editor UI mode: "classic" (light) or "dark".
    let uiMode: String
    /// Page background hex, for matching the native window chrome.
    let backgroundHex: String
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
    static let sans = #""Helvetica Neue", Helvetica, Arial, "Segoe UI", sans-serif"#
    static let serif = #""New York", "Iowan Old Style", Palatino, Georgia, Cambria, "Times New Roman", serif"#
    static let mono = #""Source Code Pro", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"#
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
                    bg: "#ffffff", surface: "#f6f8fa", fg: "#333333", faint: "#9a9a9a",
                    accent: "#4183c4", border: "#e6e6e6", quoteBar: "#dcdcdc",
                    selection: "rgba(65,131,196,0.16)", font: Fonts.sans, mono: Fonts.mono,
                    maxWidth: "800px", fontSize: "16px"),
            Palette(id: "graphite", displayName: "Graphite", uiMode: "dark",
                    bg: "#2c2c2e", surface: "#3a3a3c", fg: "#d4d4d6", faint: "#8e8e92",
                    accent: "#6cb3ff", border: "#3f3f41", quoteBar: "#4c4c4e",
                    selection: "rgba(108,179,255,0.24)", font: Fonts.sans, mono: Fonts.mono,
                    maxWidth: "800px", fontSize: "16px"),
            Palette(id: "manuscript", displayName: "Manuscript", uiMode: "classic",
                    bg: "#f5efe3", surface: "#ece2cd", fg: "#43392c", faint: "#9a8a6c",
                    accent: "#9a5b34", border: "#ddd0b8", quoteBar: "#cdbd98",
                    selection: "rgba(154,91,52,0.16)", font: Fonts.serif, mono: Fonts.mono,
                    maxWidth: "740px", fontSize: "17px"),
            Palette(id: "newsprint", displayName: "Newsprint", uiMode: "classic",
                    bg: "#fbfbf9", surface: "#efefec", fg: "#2b2b2b", faint: "#777777",
                    accent: "#1a1a1a", border: "#e3e3df", quoteBar: "#cfcfca",
                    selection: "rgba(0,0,0,0.10)", font: Fonts.serif, mono: Fonts.mono,
                    maxWidth: "760px", fontSize: "17px")
        ]
        return palettes.map {
            Theme(id: $0.id, displayName: $0.displayName, uiMode: $0.uiMode,
                  backgroundHex: $0.bg, css: readerCSS($0), editorCSS: editorCSS($0))
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
                let uiMode = id.lowercased().contains("dark") || id.lowercased().contains("night") ? "dark" : "classic"
                return Theme(id: id, displayName: name, uiMode: uiMode,
                             backgroundHex: uiMode == "dark" ? "#1e1e1e" : "#ffffff",
                             css: css, editorCSS: css)
            }
    }
}

// MARK: - Stylesheet generation

private func readerCSS(_ p: Palette) -> String {
    """
    :root{color-scheme:\(p.uiMode == "dark" ? "dark" : "light");}
    body{background:\(p.bg);color:\(p.fg);font-family:\(p.font);font-size:\(p.fontSize);line-height:1.6;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;}
    ::selection{background:\(p.selection);}
    .markdown-body{max-width:\(p.maxWidth);padding:30px 30px 120px;}
    .markdown-body>:first-child{margin-top:0;}
    h1,h2,h3,h4,h5,h6{color:\(p.fg);font-weight:700;line-height:1.3;margin:1.4em 0 .8em;}
    h1{font-size:1.9em;}
    h2{font-size:1.5em;}
    h3{font-size:1.25em;}
    h4{font-size:1.05em;}
    h5{font-size:.95em;}
    h6{font-size:.9em;color:\(p.faint);}
    p{margin:0 0 1em;}
    a{color:\(p.accent);text-decoration:none;}
    a:hover{text-decoration:underline;}
    strong{font-weight:700;}
    em{font-style:italic;}
    del{color:\(p.faint);}
    code{font-family:\(p.mono);font-size:.88em;background:\(p.surface);padding:.2em .4em;border-radius:4px;}
    pre{background:\(p.surface);padding:12px 16px;border-radius:4px;overflow:auto;line-height:1.5;margin:1em 0;}
    pre code{background:none;padding:0;font-size:.86em;}
    blockquote{margin:1em 0;padding:0 0 0 1em;border-left:4px solid \(p.quoteBar);color:\(p.faint);}
    blockquote p{margin:.4em 0;}
    hr{border:none;height:1px;background:\(p.border);margin:1.8em 0;}
    ul,ol{margin:0 0 1em;padding-left:1.6em;}
    li{margin:.25em 0;}
    li::marker{color:\(p.faint);}
    .task-list-item{list-style:none;}
    .task-list-item input{margin:0 .5em 0 -1.5em;vertical-align:middle;}
    table{border-collapse:collapse;margin:1em 0;font-size:.95em;}
    th,td{border:1px solid \(p.border);padding:6px 13px;text-align:left;}
    thead th{background:transparent;font-weight:600;}
    img{max-width:100%;height:auto;border-radius:6px;}
    """
}

private func editorCSS(_ p: Palette) -> String {
    """
    html,body{background:\(p.bg);margin:0;height:100%;}
    .vditor{border:none!important;background:\(p.bg)!important;height:auto!important;min-height:100vh;--panel-background-color:\(p.bg)!important;--textarea-background-color:\(p.bg)!important;--toolbar-background-color:\(p.bg)!important;--resize-background-color:\(p.bg)!important;}
    .vditor-toolbar{display:none!important;}
    .vditor-content{background:\(p.bg)!important;height:auto!important;overflow:visible!important;width:100%!important;}
    .vditor-ir,.vditor-wysiwyg,.vditor-sv{height:auto!important;overflow:visible!important;width:100%!important;padding:0!important;box-sizing:border-box;}
    .vditor-reset{color:\(p.fg)!important;font-family:\(p.font)!important;font-size:\(p.fontSize)!important;line-height:1.6;max-width:\(p.maxWidth)!important;margin:0 auto!important;padding:34px 44px 160px!important;-webkit-font-smoothing:antialiased;caret-color:\(p.accent);box-sizing:border-box;}
    .vditor-ir .vditor-reset>h1:before,.vditor-ir .vditor-reset>h2:before,.vditor-ir .vditor-reset>h3:before,.vditor-ir .vditor-reset>h4:before,.vditor-ir .vditor-reset>h5:before,.vditor-ir .vditor-reset>h6:before,.vditor-wysiwyg .vditor-reset>h1:before,.vditor-wysiwyg .vditor-reset>h2:before,.vditor-wysiwyg .vditor-reset>h3:before,.vditor-wysiwyg .vditor-reset>h4:before,.vditor-wysiwyg .vditor-reset>h5:before,.vditor-wysiwyg .vditor-reset>h6:before,.vditor-ir div[data-type="footnotes-block"]:before,.vditor-ir div[data-type="link-ref-defs-block"]:before,.vditor-wysiwyg div[data-type="footnotes-block"]:before,.vditor-wysiwyg div[data-type="link-ref-defs-block"]:before{content:none!important;margin:0!important;padding:0!important;}
    .vditor-ir__node,.vditor-reset h1,.vditor-reset h2,.vditor-reset h3,.vditor-reset h4,.vditor-reset h5,.vditor-reset h6,.vditor-reset p,.vditor-reset li,.vditor-reset ul,.vditor-reset ol,.vditor-reset blockquote,.vditor-reset table{background:transparent!important;}
    .vditor-reset h1,.vditor-reset h2,.vditor-reset h3,.vditor-reset h4,.vditor-reset h5,.vditor-reset h6{color:\(p.fg)!important;font-weight:700;line-height:1.3;border:none!important;padding:0!important;margin:1.4em 0 .8em!important;}
    .vditor-reset h1{font-size:1.9em;}
    .vditor-reset h2{font-size:1.5em;}
    .vditor-reset h3{font-size:1.25em;}
    .vditor-reset h4{font-size:1.05em;}
    .vditor-reset h5{font-size:.95em;}
    .vditor-reset h6{font-size:.9em;color:\(p.faint)!important;}
    .vditor-reset p{margin:0 0 1em!important;}
    .vditor-reset a{color:\(p.accent)!important;text-decoration:none;}
    .vditor-reset a:hover{text-decoration:underline;}
    .vditor-reset strong{font-weight:700;}
    .vditor-reset del{color:\(p.faint)!important;}
    .vditor-reset code:not(.hljs):not([class*="vditor-ir__marker"]){font-family:\(p.mono);background:\(p.surface);padding:.2em .4em;border-radius:4px;font-size:.88em;color:\(p.fg);}
    .vditor-reset pre{background:\(p.surface)!important;border-radius:4px;margin:1em 0;}
    .vditor-reset pre>code,.vditor-reset pre code.hljs{background:\(p.surface)!important;padding:12px 16px;font-size:.85em;border-radius:4px;display:block;}
    .vditor-reset blockquote{border-left:4px solid \(p.quoteBar)!important;color:\(p.faint)!important;padding:0 0 0 1em!important;margin:1em 0!important;}
    .vditor-reset hr{background:\(p.border);height:1px;border:none;margin:1.8em 0;}
    .vditor-reset table{border-collapse:collapse;margin:1em 0;}
    .vditor-reset table td,.vditor-reset table th{border:1px solid \(p.border)!important;padding:6px 13px!important;}
    .vditor-reset thead th{background:transparent!important;font-weight:600;}
    .vditor-reset img{border-radius:6px;}
    .vditor-reset ul,.vditor-reset ol{padding-left:1.6em;}
    .vditor-reset li{margin:.25em 0;}
    .vditor-ir__marker{color:\(p.faint)!important;opacity:.5;}
    .vditor-outline{background:\(p.surface)!important;border-right:1px solid \(p.border)!important;}
    .vditor-outline__title{color:\(p.faint)!important;}
    .vditor-outline li>span:hover{background:\(p.bg)!important;}
    .vditor-counter{color:\(p.faint)!important;background:transparent!important;border:none!important;}
    .vditor-resize{display:none!important;}
    body.ouro-focus .vditor-reset>*{opacity:.3;transition:opacity .18s ease;}
    body.ouro-focus .vditor-reset>.ouro-active,body.ouro-focus .vditor-reset>.ouro-active *{opacity:1;}
    ::selection{background:\(p.selection);}
    .vditor-reset ::selection{background:\(p.selection);}
    """
}
