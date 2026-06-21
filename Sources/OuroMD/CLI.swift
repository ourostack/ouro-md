import Foundation
import OuroMDCore

/// Command-line entry points: headless render, theme listing, help, version.
enum OuroCLI {
    static let version = OuroMDRelease.version
    static var gitSHA: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "OuroMDGitSHA") as? String
        guard let raw, !raw.isEmpty, raw != "unknown" else { return nil }
        return raw
    }
    static var versionDescription: String {
        if let gitSHA { return "\(version) (\(gitSHA))" }
        return version
    }

    static let helpText = """
    ouro-md — a minimalist, themable, native macOS Markdown editor.

    USAGE
      ouro-md [FILE]                 Open FILE (or a blank document) in the editor.
      ouro-md --render FILE [opts]   Render FILE to a self-contained HTML document
                                     on stdout (no window).
      ouro-md --list-themes          List available themes and exit.
      ouro-md --roundtrip FILE       Load FILE through the live editor and print
                                     the Markdown value returned by Vditor.
      ouro-md --renderprobe          Verify live rich-rendering support.
      ouro-md --alerttest            Verify alert-callout marker display safety.
      ouro-md --wraptest             Verify editor typing quality-of-life hooks.
      ouro-md --tablewraptest        Verify table layout and table-local scrolling.
      ouro-md --codewraptest         Verify fenced code uses block-local scrolling.
      ouro-md --visualqatest         Verify mixed visual document surfaces.
      ouro-md --searchrevealtest     Verify search result reveal semantics.
      ouro-md --uisurfacetest        Verify native Preferences/search surfaces.
      ouro-md --editorsurfacetest    Verify editor transfer/recovery/export surfaces.
      ouro-md --firstlaunchtest      Verify the first-launch welcome surface renders.
      ouro-md --liveupdatetest       Verify live older-release to latest updater flow.
      ouro-md --undotest             Verify editor undo/redo routing.
      ouro-md --help | --version

    RENDER OPTIONS
      --theme NAME                   Theme to embed (default: quartz).

    TABLE PROBE OPTIONS
      --tablewrap-file FILE          Markdown file to dogfood.
      --tablewrap-width PX           Viewport width (default: 480).
      --tablewrap-height PX          Viewport height (default: 640).
      --codewrap-width PX            Viewport width (default: 480).
      --codewrap-height PX           Viewport height (default: 640).

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
