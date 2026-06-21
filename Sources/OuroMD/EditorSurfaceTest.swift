import AppKit
import OuroMDCore
import WebKit

/// Headless `--editorsurfacetest`: exercises WebKit/editor behaviors that unit
/// tests cannot see directly: image paste/drop, file-drop classification,
/// WebContent recovery, HTML theme snapshots, and PDF generation.
@MainActor
final class EditorSurfaceTester: NSObject {
    private var model: AppModel!
    private var coordinator: EditorWebView.Coordinator!
    private var webView: EditorDropWebView!
    private var window: NSWindow!
    private var root: URL!
    private var markdownFile: URL!

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            let ok = await self.execute()
            self.cleanup()
            exit(ok ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            FileHandle.standardError.write(Data("editorsurfacetest: timed out\n".utf8))
            exit(1)
        }
        app.run()
        exit(0)
    }

    private func execute() async -> Bool {
        do {
            try prepareFixture()
            try await loadEditor()
            let dropFileOK = try verifyMarkdownFileDropClassification()
            let imagePasteOK = await verifyImageTransfer(kind: "paste", fileName: "pasted.png")
            let imageDropOK = await verifyImageTransfer(kind: "drop", fileName: "dropped.png")
            let recoveryOK = try await verifyCrashRecovery()
            let htmlOK = try verifyHTMLExports()
            let printOK = verifyPrintDryRun()
            let pdfOK = await verifyPDFExport()

            print("markdown file drop classification: \(dropFileOK ? "ok" : "FAIL")")
            print("image paste data-uri insertion: \(imagePasteOK ? "ok" : "FAIL")")
            print("image drop data-uri insertion: \(imageDropOK ? "ok" : "FAIL")")
            print("web content recovery reload: \(recoveryOK ? "ok" : "FAIL")")
            print("html exports all themes: \(htmlOK ? "ok" : "FAIL")")
            print("print dry-run operation: \(printOK ? "ok" : "FAIL")")
            print("pdf export probe: \(pdfOK ? "ok" : "FAIL")")
            return dropFileOK && imagePasteOK && imageDropOK && recoveryOK && htmlOK && printOK && pdfOK
        } catch {
            FileHandle.standardError.write(Data("editorsurfacetest: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    private func prepareFixture() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-editor-surface-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        markdownFile = root.appendingPathComponent("surface.md")
        try Self.initialMarkdown.write(to: markdownFile, atomically: true, encoding: .utf8)
    }

    private func loadEditor() async throws {
        model = AppModel()
        model.presentErrorHandler = { message, error in
            FileHandle.standardError.write(Data("\(message): \(error.localizedDescription)\n".utf8))
        }
        _ = model.loadInitialFile(markdownFile.path)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        coordinator = EditorWebView.Coordinator(model: model)
        controller.add(coordinator, name: "ouro")
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: 760, height: 900)
        webView = EditorDropWebView(frame: frame, configuration: configuration)
        webView.model = model
        webView.navigationDelegate = coordinator
        webView.registerForDraggedTypes([.fileURL])
        coordinator.webView = webView
        model.bridge = coordinator

        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let indexURL = OuroResources.web("index", "html") else {
            throw SurfaceError("index.html not found")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        guard await waitUntil(timeout: 8, condition: { self.model.isReady }) else {
            throw SurfaceError("editor did not become ready")
        }
        guard await waitForMarkdown(containing: "Surface Probe", timeout: 8) else {
            throw SurfaceError("initial markdown did not load")
        }
    }

    private func verifyMarkdownFileDropClassification() throws -> Bool {
        let dropped = root.appendingPathComponent("dropped.md")
        let ignored = root.appendingPathComponent("ignored.png")
        try "# dropped".write(to: dropped, atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: ignored)

        let accepted = NSPasteboard(name: NSPasteboard.Name("ouro-surface-drop-\(UUID().uuidString)"))
        accepted.clearContents()
        guard accepted.writeObjects([dropped as NSURL]),
              EditorDropWebView.openableMarkdownURL(from: accepted) == dropped else {
            return false
        }

        let rejected = NSPasteboard(name: NSPasteboard.Name("ouro-surface-drop-\(UUID().uuidString)"))
        rejected.clearContents()
        return rejected.writeObjects([ignored as NSURL])
            && EditorDropWebView.openableMarkdownURL(from: rejected) == nil
    }

    private func verifyImageTransfer(kind: String, fileName: String) async -> Bool {
        let before = (await markdownValue()) ?? ""
        _ = await evaluate(Self.transferScript(kind: kind, fileName: fileName))
        guard await waitForMarkdown(containing: "![\(fileName)](data:image/png;base64", timeout: 8) else {
            return false
        }
        let after = (await markdownValue()) ?? ""
        return after.count > before.count
    }

    private func verifyCrashRecovery() async throws -> Bool {
        try Self.recoveredMarkdown.write(to: markdownFile, atomically: true, encoding: .utf8)
        coordinator.webViewWebContentProcessDidTerminate(webView)
        guard await waitUntil(timeout: 8, condition: { self.model.isReady }) else { return false }
        return await waitForMarkdown(containing: "Recovered After Crash", timeout: 8)
    }

    private func verifyHTMLExports() throws -> Bool {
        let body = MarkdownRenderer.renderHTMLBody(Self.exportMarkdown, baseDirectory: root)
        for theme in ThemeStore.shared.themes {
            let html = HTMLDocument.wrap(body: body, css: theme.css, title: "export-\(theme.id).html")
            let out = root.appendingPathComponent("export-\(theme.id).html")
            try html.write(to: out, atomically: true, encoding: .utf8)
            let saved = try String(contentsOf: out, encoding: .utf8)
            guard saved.contains("<!DOCTYPE html>"),
                  saved.contains("class=\"markdown-body\""),
                  saved.contains(theme.css),
                  saved.contains("Export Probe"),
                  saved.contains("data:image/svg+xml;base64") else {
                return false
            }
        }
        return true
    }

    private func verifyPrintDryRun() -> Bool {
        let operation = webView.printOperation(with: NSPrintInfo())
        operation.view?.frame = webView.bounds
        return operation.view != nil && operation.printInfo.paperSize.width > 0
    }

    private func verifyPDFExport() async -> Bool {
        let body = MarkdownRenderer.renderHTMLBody(Self.exportMarkdown, baseDirectory: root)
        let html = HTMLDocument.wrap(
            body: body,
            css: ThemeStore.shared.defaultTheme.css,
            title: "export.pdf"
        )
        let out = root.appendingPathComponent("export.pdf")
        let ok = await withCheckedContinuation { continuation in
            PDFExporter().export(html: html, to: out) { rendered in
                continuation.resume(returning: rendered)
            }
        }
        guard ok, let data = try? Data(contentsOf: out), data.count > 1_000 else {
            return false
        }
        return data.prefix(4) == Data("%PDF".utf8)
    }

    private func markdownValue() async -> String? {
        await evaluate("window.ouro ? window.ouro.getValue() : null") as? String
    }

    private func waitForMarkdown(containing needle: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if ((await markdownValue()) ?? "").contains(needle) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return ((await markdownValue()) ?? "").contains(needle)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func evaluate(_ javascript: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(javascript) { result, error in
                if let error {
                    FileHandle.standardError.write(Data("editorsurfacetest js: \(error.localizedDescription)\n".utf8))
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func cleanup() {
        model?.teardown()
        window?.orderOut(nil)
        try? FileManager.default.removeItem(at: root)
    }

    private static func transferScript(kind: String, fileName: String) -> String {
        """
        (function () {
          if (typeof DataTransfer !== "function" || typeof File !== "function") { return "missing constructors"; }
          var binary = atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=");
          var bytes = new Uint8Array(binary.length);
          for (var i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
          var file = new File([bytes], "\(fileName)", { type: "image/png" });
          var dt = new DataTransfer();
          dt.items.add(file);
          var target = document.getElementById("editor");
          if (!target) { return "missing editor"; }
          var event;
          if ("\(kind)" === "paste") {
            event = new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: dt });
          } else {
            event = new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt });
          }
          target.dispatchEvent(event);
          return "dispatched";
        })();
        """
    }

    private static let initialMarkdown = """
    # Surface Probe

    Initial document.
    """

    private static let recoveredMarkdown = """
    # Surface Probe

    Recovered After Crash.
    """

    private static let exportMarkdown = """
    # Export Probe

    A paragraph with **bold** text and a table.

    | Theme | Evidence |
    | --- | --- |
    | Quartz | HTML export |

    ![fixture](data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxIiBoZWlnaHQ9IjEiPjxyZWN0IHdpZHRoPSIxIiBoZWlnaHQ9IjEiIGZpbGw9IiMwMDAiLz48L3N2Zz4=)
    """

    private struct SurfaceError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
