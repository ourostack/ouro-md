import AppKit
import OuroMDCore

/// Headless `--markdownparitytest`: verifies the pure renderer, themed HTML
/// wrapper, and PDF exporter preserve the same core Markdown feature fixture.
@MainActor
final class MarkdownParityTester {
    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        Task { @MainActor in
            let ok = await self.execute()
            exit(ok ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            FileHandle.standardError.write(Data("markdownparitytest: timed out\n".utf8))
            exit(1)
        }
        app.run()
        exit(0)
    }

    private func execute() async -> Bool {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-markdown-parity-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data([0x89, 0x50, 0x4e, 0x47]).write(to: root.appendingPathComponent("pixel.png"))
            let markdown = Self.fixture
            let body = MarkdownRenderer.renderHTMLBody(markdown, baseDirectory: root)
            let bodyChecks = [
                ("heading id", body.contains("<h1 id=\"parity-fixture\">")),
                ("link", body.contains("<a href=\"https://example.com/path?x=1&amp;y=2\">")),
                ("local image", body.contains("data:image/png;base64")),
                ("task list", body.contains("class=\"task-list-item\"") && body.contains("checked")),
                ("table", body.contains("<table>") && body.contains("style=\"text-align:right\"")),
                ("raw html", body.contains("<kbd>Cmd</kbd>") && body.contains("<br>")),
                ("footnotes", body.contains("<section class=\"footnotes\">") && body.contains("class=\"footnote-backref\"")),
                ("mermaid fence", body.contains("class=\"language-mermaid\"")),
                ("math fence", body.contains("class=\"language-math\"")),
                ("escaped text", body.contains("&lt;escaped&gt;")),
            ]
            let bodyOK = report("renderer", bodyChecks)

            var htmlOK = true
            for theme in ThemeStore.shared.themes {
                let wrapped = HTMLDocument.wrap(body: body, css: theme.css, title: "Parity <\(theme.id)>")
                let out = root.appendingPathComponent("parity-\(theme.id).html")
                try wrapped.write(to: out, atomically: true, encoding: .utf8)
                let saved = try String(contentsOf: out, encoding: .utf8)
                let checks = [
                    ("doctype", saved.contains("<!DOCTYPE html>")),
                    ("article", saved.contains("class=\"markdown-body\"")),
                    ("escaped title", saved.contains("Parity &lt;\(theme.id)&gt;")),
                    ("theme css", saved.contains(theme.css)),
                    ("feature body", saved.contains("Parity Fixture") && saved.contains("footnote-backref")),
                ]
                htmlOK = report("html \(theme.id)", checks) && htmlOK
            }

            let pdfOK = await verifyPDF(body: body, root: root)
            try? FileManager.default.removeItem(at: root)
            return bodyOK && htmlOK && pdfOK
        } catch {
            try? FileManager.default.removeItem(at: root)
            FileHandle.standardError.write(Data("markdownparitytest: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    private func verifyPDF(body: String, root: URL) async -> Bool {
        let html = HTMLDocument.wrap(body: body, css: ThemeStore.shared.defaultTheme.css, title: "parity.pdf")
        let out = root.appendingPathComponent("parity.pdf")
        let rendered = await withCheckedContinuation { continuation in
            PDFExporter().export(html: html, to: out) { ok in
                continuation.resume(returning: ok)
            }
        }
        let data = (try? Data(contentsOf: out)) ?? Data()
        let ok = rendered && data.prefix(4) == Data("%PDF".utf8) && data.count > 1_000
        print("pdf export parity: \(ok ? "✓" : "✗") bytes=\(data.count)")
        return ok
    }

    private func report(_ label: String, _ checks: [(String, Bool)]) -> Bool {
        let failed = checks.filter { !$0.1 }.map(\.0)
        print("\(label) parity: \(failed.isEmpty ? "✓" : "✗")")
        if !failed.isEmpty {
            print("\(label) missing: \(failed.joined(separator: " | "))")
        }
        return failed.isEmpty
    }

    private static let fixture = """
    # Parity Fixture

    Paragraph with **bold**, *italic*, `inline code`, <span>raw html</span>, and &lt;escaped&gt; text.

    [Example](https://example.com/path?x=1&y=2)

    ![local pixel](pixel.png)

    - [x] complete
    - [ ] pending

    | Left | Center | Right |
    | :--- | :----: | ----: |
    | <kbd>Cmd</kbd><br>HTML | `Sources/OuroMD/Parity.swift` | 42 |

    Body with footnote[^note].

    [^note]: Footnote **body** with [back link](https://example.com).

    ```math
    E = mc^2
    ```

    ```mermaid
    graph TD; A-->B;
    ```
    """
}
