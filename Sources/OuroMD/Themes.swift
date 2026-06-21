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
///
/// The default theme ("quartz") carries a GitHub-style light document palette.
/// The remaining themes are ouro-original recolorings of the same structure.
private struct Palette {
    let id: String
    let displayName: String
    let uiMode: String
    let bg: String            // page background
    let fg: String            // body text
    let faint: String         // h6, blockquote text, del
    let accent: String        // links + caret
    let headingRule: String   // h1/h2 underline
    let hrColor: String       // horizontal rule
    let quoteBar: String      // blockquote left border
    let cellBorder: String    // table cell/row border
    let tableFill: String     // table header + even-row zebra
    let codeBlockBg: String   // fenced code background
    let inlineCodeBg: String  // inline code background
    let codeBorder: String    // code border (inline + block)
    let marker: String        // IR syntax markers / md-tag
    let selection: String     // text selection background
    let sidebarBg: String     // sidebar / outline background
    /// Apply the editor's light syntax palette. Dark themes keep Vditor's
    /// bundled dark hljs theme instead.
    let lightCodeSyntax: Bool
}

private enum Fonts {
    /// Global body font. "Open Sans" is bundled (Apache-2.0).
    static let sans = #""Open Sans", "Clear Sans", "Helvetica Neue", Helvetica, Arial, "Segoe UI Emoji", sans-serif"#
    /// Global code font. Menlo leads the macOS fallback to avoid the thin
    /// rendering of Courier-style monospace faces.
    static let mono = #""Lucida Console", Consolas, Menlo, Monaco, monospace"#
    /// Global root font size.
    static let size = "16px"
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
            // Quartz — GitHub-style light document theme.
            Palette(id: "quartz", displayName: "Quartz", uiMode: "classic",
                    bg: "#ffffff", fg: "#333333", faint: "#777777", accent: "#4183c4",
                    headingRule: "#eeeeee", hrColor: "#e7e7e7", quoteBar: "#dfe2e5",
                    cellBorder: "#dfe2e5", tableFill: "#f8f8f8", codeBlockBg: "#f8f8f8",
                    inlineCodeBg: "#f3f4f4", codeBorder: "#e7eaed", marker: "#a7a7a7",
                    selection: "#b5d6fc", sidebarBg: "#fafafa",
                    lightCodeSyntax: true),
            // Graphite — ouro-original dark theme.
            Palette(id: "graphite", displayName: "Graphite", uiMode: "dark",
                    bg: "#2c2c2e", fg: "#e4e4e6", faint: "#9a9a9e", accent: "#6cb3ff",
                    headingRule: "#3f3f41", hrColor: "#3f3f41", quoteBar: "#4c4c4e",
                    cellBorder: "#3f3f41", tableFill: "#3a3a3c", codeBlockBg: "#1f1f21",
                    inlineCodeBg: "#3a3a3c", codeBorder: "#3f3f41", marker: "#7a7a7e",
                    selection: "rgba(108,179,255,0.24)", sidebarBg: "#262628",
                    lightCodeSyntax: false),
            // Manuscript — ouro-original warm serif theme.
            Palette(id: "manuscript", displayName: "Manuscript", uiMode: "classic",
                    bg: "#f5efe3", fg: "#43392c", faint: "#9a8a6c", accent: "#9a5b34",
                    headingRule: "#ddd0b8", hrColor: "#ddd0b8", quoteBar: "#cdbd98",
                    cellBorder: "#ddd0b8", tableFill: "#ece2cd", codeBlockBg: "#ece2cd",
                    inlineCodeBg: "#ece2cd", codeBorder: "#ddd0b8", marker: "#b5a585",
                    selection: "rgba(154,91,52,0.16)", sidebarBg: "#efe7d5",
                    lightCodeSyntax: true),
            // Newsprint — ouro-original cool serif theme.
            Palette(id: "newsprint", displayName: "Newsprint", uiMode: "classic",
                    bg: "#fbfbf9", fg: "#2b2b2b", faint: "#777777", accent: "#1a1a1a",
                    headingRule: "#e3e3df", hrColor: "#e3e3df", quoteBar: "#cfcfca",
                    cellBorder: "#e3e3df", tableFill: "#efefec", codeBlockBg: "#efefec",
                    inlineCodeBg: "#efefec", codeBorder: "#e3e3df", marker: "#9a9a9a",
                    selection: "rgba(0,0,0,0.10)", sidebarBg: "#f3f3f0",
                    lightCodeSyntax: true)
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

// MARK: - Code syntax palette (CodeMirror `cm-s-inner`)

/// highlight.js token overrides matching the CodeMirror `cm-s-inner` palette.
/// Vditor renders fences with highlight.js, so we re-map hljs classes to those
/// colors. Colors only — the block background/border come from the per-theme
/// rules so warm/cool light themes keep their own surface.
private func codeSyntaxCSS(_ p: Palette) -> String {
    guard p.lightCodeSyntax else { return "" }
    return """
    .vditor-reset .hljs-keyword,.vditor-reset .hljs-selector-tag,.vditor-reset .hljs-section{color:#770088!important;}
    .vditor-reset .hljs-literal,.vditor-reset .hljs-symbol,.vditor-reset .hljs-bullet{color:#221199!important;}
    .vditor-reset .hljs-number{color:#116644!important;}
    .vditor-reset .hljs-title,.vditor-reset .hljs-title.function_,.vditor-reset .hljs-doctag{color:#0000ff!important;}
    .vditor-reset .hljs-variable,.vditor-reset .hljs-property,.vditor-reset .hljs-params{color:#000000!important;}
    .vditor-reset .hljs-template-variable,.vditor-reset .hljs-variable.language_{color:#0055aa!important;}
    .vditor-reset .hljs-type,.vditor-reset .hljs-class .hljs-title,.vditor-reset .hljs-title.class_{color:#008855!important;}
    .vditor-reset .hljs-string,.vditor-reset .hljs-meta .hljs-string{color:#aa1111!important;}
    .vditor-reset .hljs-operator{color:#981a1a!important;}
    .vditor-reset .hljs-comment,.vditor-reset .hljs-quote{color:#aa5500!important;}
    .vditor-reset .hljs-regexp{color:#ff5500!important;}
    .vditor-reset .hljs-meta,.vditor-reset .hljs-meta .hljs-keyword{color:#555555!important;}
    .vditor-reset .hljs-built_in{color:#3300aa!important;}
    .vditor-reset .hljs-tag,.vditor-reset .hljs-name{color:#117700!important;}
    .vditor-reset .hljs-attr,.vditor-reset .hljs-attribute,.vditor-reset .hljs-link,.vditor-reset .hljs-selector-attr{color:#0000cc!important;}
    .vditor-reset .hljs-built_in.hljs-emphasis{color:#3300aa!important;}
    """
}

// MARK: - Stylesheet generation

/// Standalone-document CSS (for `--render` / HTML export). Mirrors the Github
/// theme so exported files match the editor.
private func readerCSS(_ p: Palette) -> String {
    """
    :root{color-scheme:\(p.uiMode == "dark" ? "dark" : "light");}
    html{font-size:\(Fonts.size);}
    body{background:\(p.bg);color:\(p.fg);font-family:\(Fonts.sans);line-height:1.6;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;margin:0;}
    ::selection{background:\(p.selection);}
    .markdown-body{max-width:860px;margin:0 auto;padding:30px 30px 100px;--ouro-table-viewport:calc(100vw - 24px);}
    @media (min-width:1400px){.markdown-body{max-width:1024px;}}
    @media (min-width:1800px){.markdown-body{max-width:1200px;}}
    .markdown-body>:first-child{margin-top:0;}
    h1,h2,h3,h4,h5,h6{color:\(p.fg);font-weight:bold;line-height:1.4;margin:1rem 0;}
    h1{font-size:2.25em;line-height:1.2;border-bottom:1px solid \(p.headingRule);}
    h2{font-size:1.75em;line-height:1.225;border-bottom:1px solid \(p.headingRule);}
    h3{font-size:1.5em;line-height:1.43;}
    h4{font-size:1.25em;}
    h5{font-size:1em;}
    h6{font-size:1em;color:\(p.faint);}
    p,blockquote,ul,ol,dl{margin:0.8em 0;}
    a{color:\(p.accent);text-decoration:none;}
    a:hover{text-decoration:underline;}
    strong{font-weight:bold;}
    em{font-style:italic;}
    del{color:\(p.faint);}
    code{font-family:\(Fonts.mono);font-size:0.9em;background:\(p.inlineCodeBg);border:1px solid \(p.codeBorder);border-radius:3px;padding:0 2px;}
    pre{background:\(p.codeBlockBg);border:1px solid \(p.codeBorder);border-radius:3px;padding:8px 10px;overflow:auto;line-height:1.5;margin:15px 0;}
    pre code{background:none;border:none;padding:0;font-size:0.9em;}
    blockquote{padding:0 15px;border-left:4px solid \(p.quoteBar);color:\(p.faint);}
    hr{border:0;height:2px;background:\(p.hrColor);margin:16px 0;padding:0;}
    ul,ol{padding-left:30px;}
    li{margin:0.25em 0;}
    .task-list-item{list-style:none;}
    .task-list-item input{margin:0 .5em 0 -1.3em;vertical-align:middle;}
    table{border-collapse:collapse;display:block;overflow-x:auto;width:max-content;min-width:100%;max-width:var(--ouro-table-viewport);margin:0.8em 0;margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2));margin-right:min(0px, calc((100% - var(--ouro-table-viewport)) / 2));table-layout:auto;text-align:left;-webkit-overflow-scrolling:touch;}
    table tr{border:1px solid \(p.cellBorder);}
    table tr:nth-child(2n),thead{background:\(p.tableFill);}
    th{font-weight:bold;border:1px solid \(p.cellBorder);border-bottom:0;padding:6px 13px;white-space:normal;overflow-wrap:normal;word-break:normal;vertical-align:top;min-width:16rem;max-width:42rem;}
    td{border:1px solid \(p.cellBorder);padding:6px 13px;white-space:normal;overflow-wrap:normal;word-break:normal;vertical-align:top;min-width:16rem;max-width:42rem;}
    th.ouro-code-only-cell,td.ouro-code-only-cell{min-width:max-content;max-width:none;}
    td code,th code{white-space:nowrap;display:inline-block;max-width:100%;overflow-x:auto;vertical-align:bottom;}
    img{max-width:100%;}
    """
}

/// Live-editor CSS, injected into the Vditor surface. Targets `.vditor-reset`
/// and re-skins Vditor to the app's document themes.
private func editorCSS(_ p: Palette) -> String {
    """
    html,body{background:\(p.bg);margin:0;height:100%;}
    .vditor{border:none!important;background:\(p.bg)!important;height:auto!important;min-height:100vh;--panel-background-color:\(p.bg)!important;--textarea-background-color:\(p.bg)!important;--toolbar-background-color:\(p.bg)!important;--resize-background-color:\(p.bg)!important;}
    .vditor-toolbar{display:none!important;}
    .vditor{overflow:visible!important;}
    .vditor-content{background:\(p.bg)!important;height:auto!important;overflow:visible!important;width:100%!important;}
    .vditor-ir,.vditor-wysiwyg,.vditor-sv{height:auto!important;overflow:visible!important;width:100%!important;padding:0!important;box-sizing:border-box;}

    /* Content column — centered, responsive max-width (Github theme). Width is
       global across themes; a theme changes type + color, never the measure. */
    .vditor-reset{color:\(p.fg)!important;font-family:\(Fonts.sans)!important;font-size:\(Fonts.size)!important;line-height:1.6!important;max-width:860px!important;margin:0 auto!important;padding:30px 30px 100px!important;-webkit-font-smoothing:antialiased;caret-color:\(p.accent);box-sizing:border-box;overflow:visible!important;--ouro-table-viewport:calc(100vw - 24px);}
    @media (min-width:1400px){.vditor-reset{max-width:1024px!important;}}
    @media (min-width:1800px){.vditor-reset{max-width:1200px!important;}}

    /* Strip Vditor's H1–H6 gutter badges + block labels. */
    .vditor-ir .vditor-reset>h1:before,.vditor-ir .vditor-reset>h2:before,.vditor-ir .vditor-reset>h3:before,.vditor-ir .vditor-reset>h4:before,.vditor-ir .vditor-reset>h5:before,.vditor-ir .vditor-reset>h6:before,.vditor-wysiwyg .vditor-reset>h1:before,.vditor-wysiwyg .vditor-reset>h2:before,.vditor-wysiwyg .vditor-reset>h3:before,.vditor-wysiwyg .vditor-reset>h4:before,.vditor-wysiwyg .vditor-reset>h5:before,.vditor-wysiwyg .vditor-reset>h6:before,.vditor-ir div[data-type="footnotes-block"]:before,.vditor-ir div[data-type="link-ref-defs-block"]:before,.vditor-wysiwyg div[data-type="footnotes-block"]:before,.vditor-wysiwyg div[data-type="link-ref-defs-block"]:before{content:none!important;margin:0!important;padding:0!important;}
    .vditor-ir__node,.vditor-reset h1,.vditor-reset h2,.vditor-reset h3,.vditor-reset h4,.vditor-reset h5,.vditor-reset h6,.vditor-reset p,.vditor-reset li,.vditor-reset ul,.vditor-reset ol,.vditor-reset blockquote,.vditor-reset table{background:transparent!important;}

    /* Headings (Github exact). */
    .vditor-reset h1,.vditor-reset h2,.vditor-reset h3,.vditor-reset h4,.vditor-reset h5,.vditor-reset h6{color:\(p.fg)!important;font-weight:bold!important;line-height:1.4!important;border:none;padding:0!important;margin:1rem 0!important;position:relative;}
    .vditor-reset h1{font-size:2.25em!important;line-height:1.2!important;border-bottom:1px solid \(p.headingRule)!important;}
    .vditor-reset h2{font-size:1.75em!important;line-height:1.225!important;border-bottom:1px solid \(p.headingRule)!important;}
    .vditor-reset h3{font-size:1.5em!important;line-height:1.43!important;}
    .vditor-reset h4{font-size:1.25em!important;}
    .vditor-reset h5{font-size:1em!important;}
    .vditor-reset h6{font-size:1em!important;color:\(p.faint)!important;}
    .vditor-reset h1 code,.vditor-reset h2 code,.vditor-reset h3 code,.vditor-reset h4 code,.vditor-reset h5 code,.vditor-reset h6 code{font-size:inherit!important;}

    /* Block rhythm. */
    .vditor-reset p{margin:0.8em 0!important;}
    .vditor-reset>:first-child{margin-top:0!important;}
    .vditor-reset a{color:\(p.accent)!important;text-decoration:none;}
    .vditor-reset a:hover{text-decoration:underline;}
    .vditor-reset strong{font-weight:bold;}
    .vditor-reset del{color:\(p.faint)!important;}

    /* Inline code + fenced code (Github exact). */
    .vditor-reset code:not(.hljs):not([class*="vditor-ir__marker"]){font-family:\(Fonts.mono)!important;background:\(p.inlineCodeBg)!important;border:1px solid \(p.codeBorder)!important;border-radius:3px;padding:0 2px;font-size:0.9em;color:\(p.fg);}
    .vditor-reset pre{background:\(p.codeBlockBg)!important;border:1px solid \(p.codeBorder)!important;border-radius:3px!important;margin:15px 0!important;padding:0!important;}
    .vditor-reset pre>code,.vditor-reset pre code.hljs{background:\(p.codeBlockBg)!important;font-family:\(Fonts.mono)!important;font-size:0.9em!important;padding:8px 10px!important;border:none!important;border-radius:3px;display:block;line-height:1.5;color:\(p.fg);}

    /* IR blocks: show only the rendered preview; hide raw source + fence
       markers until the block is focused for editing. */
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) .vditor-ir__marker--pre,
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) [data-type="code-block-open-marker"],
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) [data-type="code-block-close-marker"],
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) [data-type="code-block-info"],
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) [data-type="math-block-open-marker"],
    .vditor-reset .vditor-ir__node:not(.vditor-ir__node--expand) [data-type="math-block-close-marker"]{display:none!important;}

    /* Display math: plain background, centered, no code-style box. */
    .vditor-reset .vditor-ir__node[data-type="math-block"] pre,
    .vditor-reset .vditor-ir__node[data-type="math-block"] .vditor-ir__preview{background:transparent!important;border:none!important;padding:0!important;}
    .vditor-reset .vditor-ir__node[data-type="math-block"]{margin:1em 0!important;}
    .vditor-reset .katex-display{margin:0.5em 0!important;}

    /* Code blocks: tidy spacing — drop Vditor's node pseudo-labels and the
       stacked margins so the fence sits snug under its heading/paragraph. */
    .vditor-reset .vditor-ir__node[data-type="code-block"]:before,
    .vditor-reset .vditor-ir__node[data-type="code-block"]:after{content:none!important;}
    .vditor-reset .vditor-ir__node[data-type="code-block"]{margin:0.8em 0!important;}
    .vditor-reset .vditor-ir__node[data-type="code-block"] pre.vditor-ir__preview{margin:0!important;}

    /* Blockquote, hr, lists (Github exact). */
    .vditor-reset blockquote{border-left:4px solid \(p.quoteBar)!important;color:\(p.faint)!important;padding:0 15px!important;margin:0.8em 0!important;}
    .vditor-reset hr{background:\(p.hrColor);height:2px;border:none;margin:16px 0;padding:0;}
    .vditor-reset ul,.vditor-reset ol{padding-left:30px!important;margin:0.8em 0!important;}
    .vditor-reset li{margin:0.25em 0;}

    /* Tables (Github exact): #dfe2e5 borders, #f8f8f8 header + even rows, 6px 13px cells. */
    .vditor-reset table{border-collapse:collapse!important;display:block!important;overflow-x:auto!important;width:max-content!important;min-width:100%!important;max-width:var(--ouro-table-viewport)!important;margin:0.8em 0!important;margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2))!important;margin-right:min(0px, calc((100% - var(--ouro-table-viewport)) / 2))!important;table-layout:auto;text-align:left;-webkit-overflow-scrolling:touch;}
    .vditor-reset table tr{border:1px solid \(p.cellBorder)!important;background:\(p.bg)!important;}
    .vditor-reset table tr:nth-child(2n){background:\(p.tableFill)!important;}
    .vditor-reset table thead,.vditor-reset table thead tr,.vditor-reset table th{background:\(p.tableFill)!important;}
    .vditor-reset table th{font-weight:bold;border:1px solid \(p.cellBorder)!important;border-bottom:0!important;padding:6px 13px!important;color:\(p.fg)!important;white-space:normal!important;overflow-wrap:normal!important;word-break:normal!important;vertical-align:top!important;min-width:16rem;max-width:42rem;}
    .vditor-reset table td{border:1px solid \(p.cellBorder)!important;padding:6px 13px!important;color:\(p.fg)!important;background:transparent!important;white-space:normal!important;overflow-wrap:normal!important;word-break:normal!important;vertical-align:top!important;min-width:16rem;max-width:42rem;}
    .vditor-reset table th.ouro-code-only-cell,.vditor-reset table td.ouro-code-only-cell{min-width:max-content!important;max-width:none!important;}
    .vditor-reset table td code,.vditor-reset table th code{white-space:nowrap!important;display:inline-block!important;max-width:100%!important;overflow-x:auto!important;vertical-align:bottom!important;}

    .vditor-reset img{max-width:100%;}

    /* IR syntax markers. */
    .vditor-ir__marker{color:\(p.marker)!important;}

    /* Sidebar / outline chrome; remove Vditor's footer counter + resize handle. */
    .vditor-outline{background:\(p.sidebarBg)!important;border-right:1px solid \(p.codeBorder)!important;}
    .vditor-outline__title{color:\(p.faint)!important;}
    .vditor-outline li>span:hover{background:\(p.bg)!important;}
    .vditor-counter{display:none!important;}
    .vditor-resize{display:none!important;}

    /* Focus mode. */
    body.ouro-focus .vditor-reset>*{opacity:.3;transition:opacity .18s ease;}
    body.ouro-focus .vditor-reset>.ouro-active,body.ouro-focus .vditor-reset>.ouro-active *{opacity:1;}

    ::selection{background:\(p.selection);}
    .vditor-reset ::selection{background:\(p.selection);}
    \(codeSyntaxCSS(p))
    """
}
