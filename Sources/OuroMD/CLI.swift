import Foundation

/// Command-line entry points: headless render, theme listing, help, version.
enum OuroCLI {
    static let version = "0.1.0"

    static let helpText = """
    ouro-md — a minimalist, themable, native macOS Markdown editor.

    USAGE
      ouro-md [FILE]                 Open FILE (or a blank document) in the editor.
      ouro-md --render FILE [opts]   Render FILE to a self-contained HTML document
                                     on stdout (no window).
      ouro-md --list-themes          List available themes and exit.
      ouro-md --help | --version

    RENDER OPTIONS
      --theme NAME                   Theme to embed (default: quartz).

    THEMES
      Built-in: quartz (light), graphite (dark), manuscript (sepia serif),
      newsprint (editorial). Drop your own .css files in
        ~/Library/Application Support/ouro-md/Themes/
      to add custom themes.
    """

    /// Renders a Markdown file to a complete themed HTML document on stdout.
    static func render(path: String, themeId: String) -> Never {
        let url = URL(fileURLWithPath: path)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let body = MarkdownRenderer.renderHTMLBody(markdown, baseDirectory: url.deletingLastPathComponent())
            let theme = ThemeStore.shared.theme(id: themeId)
            let html = HTMLDocument.wrap(body: body, css: theme.css, title: url.lastPathComponent)
            FileHandle.standardOutput.write(Data(html.utf8))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("ouro-md: cannot read \(path): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
