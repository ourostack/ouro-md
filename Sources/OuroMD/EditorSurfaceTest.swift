import AppKit
import OuroMDCore
import PDFKit
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
    private let printPreferences = ScratchUserDefaults(label: "print-journey")
    private var acceptanceInput: URL? {
        ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_FILE"].map { URL(fileURLWithPath: $0) }
    }

    func run() -> Never {
        let app = NSApplication.shared
        HeadlessHarness.configure()
        Task { @MainActor in
            let ok = await self.execute()
            self.cleanup()
            exit(ok ? 0 : 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (acceptanceInput == nil ? 60 : 600)) {
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
            if acceptanceInput != nil { return try await verifyLocalDocumentPrint() }
            let dropFileOK = try verifyMarkdownFileDropClassification()
            let imagePasteOK = await verifyImageTransfer(kind: "paste", fileName: "pasted.png")
            let imageDropOK = await verifyImageTransfer(kind: "drop", fileName: "dropped.png")
            let recoveryOK = try await verifyCrashRecovery()
            let htmlOK = try verifyHTMLExports()
            let printOK = verifyPrintDryRun()
            let pdfOK = await verifyPDFExport()
            let sharedPDFOK = try await verifySharedPDFJourney()

            print("markdown file drop classification: \(dropFileOK ? "ok" : "FAIL")")
            print("image paste data-uri insertion: \(imagePasteOK ? "ok" : "FAIL")")
            print("image drop data-uri insertion: \(imageDropOK ? "ok" : "FAIL")")
            print("web content recovery reload: \(recoveryOK ? "ok" : "FAIL")")
            print("html exports all themes: \(htmlOK ? "ok" : "FAIL")")
            print("print dry-run operation: \(printOK ? "ok" : "FAIL")")
            print("pdf export probe: \(pdfOK ? "ok" : "FAIL")")
            print("shared print layout controls, export and cancellation: \(sharedPDFOK ? "ok" : "FAIL")")
            return dropFileOK && imagePasteOK && imageDropOK && recoveryOK && htmlOK && printOK && pdfOK && sharedPDFOK
        } catch {
            FileHandle.standardError.write(Data("editorsurfacetest: \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    private func prepareFixture() throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("ouro-editor-surface-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        print("editor surface owned scratch: \(root.path)")
        markdownFile = root.appendingPathComponent("surface.md")
        if let input = acceptanceInput {
            markdownFile = input
        } else {
            try Self.initialMarkdown.write(to: markdownFile, atomically: true, encoding: .utf8)
        }
    }

    private func loadEditor() async throws {
        model = AppModel()
        model.presentErrorHandler = { message, error in
            FileHandle.standardError.write(Data("\(message): \(error.localizedDescription)\n".utf8))
        }
        _ = model.loadInitialFile(markdownFile.path)

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        coordinator = EditorWebView.Coordinator(model: model, printSettingsStore: PrintLayoutSettingsStore(preferences: printPreferences.defaults), pageSetupChooser: { info in
            info.paperSize = NSSize(width: 595, height: 842)
            return true
        }, printPanelChooser: { _ in false })
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

        window = HeadlessHarness.offscreenHostActive(webView, size: frame.size)

        guard let indexURL = OuroResources.web("index", "html") else {
            throw SurfaceError("index.html not found")
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        guard await waitUntil(timeout: 8, condition: { self.model.isReady }) else {
            throw SurfaceError("editor did not become ready")
        }
        if acceptanceInput == nil {
            guard await waitForMarkdown(containing: "Surface Probe", timeout: 8) else {
                throw SurfaceError("initial markdown did not load")
            }
        }
    }

    private func verifyLocalDocumentPrint() async throws -> Bool {
        guard let outputPath = ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_PDF"] else {
            throw SurfaceError("A private output path is required for local print acceptance.")
        }
        let before = try Data(contentsOf: markdownFile)
        let output = URL(fileURLWithPath: outputPath)
        var settings = PrintLayoutSettings.default
        settings.citationMode = .pageFootnotes
        settings.headingBreakLevel = Int(ProcessInfo.processInfo.environment["OURO_PRINT_HEADING_BREAK_LEVEL"] ?? "0") ?? 0
        PrintLayoutSettingsStore(preferences: printPreferences.defaults).save(settings)
        FileHandle.standardError.write(Data("local print acceptance: requesting product export\n".utf8))
        var exported: Bool?
        model.exportPDF(to: output) { exported = $0 }
        guard await waitUntil(timeout: 240, condition: { self.window.attachedSheet?.title == "Export PDF Layout" }),
              let panel = window.attachedSheet, let view = panel.contentView,
              let button = descendants(of: view).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Export PDF" }) else {
            throw SurfaceError("Product print layout did not open for the local document.")
        }
        panel.alphaValue = 0
        FileHandle.standardError.write(Data("local print acceptance: waiting for full preview\n".utf8))
        guard await waitUntil(timeout: 240, condition: { button.isEnabled }) else {
            throw SurfaceError("Full document print preview did not finish.")
        }
        button.performClick(nil)
        guard await waitUntil(timeout: 30, condition: { exported != nil }), exported == true,
              let pdf = PDFDocument(url: output) else {
            throw SurfaceError("Product print export did not produce a readable PDF.")
        }
        var emptyPages = 0
        for index in 0..<pdf.pageCount {
            if (pdf.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { emptyPages += 1 }
        }
        let unchanged = try Data(contentsOf: markdownFile) == before
        FileHandle.standardError.write(Data("local print acceptance: bytes=\(before.count) pages=\(pdf.pageCount) emptyPages=\(emptyPages) sourceUnchanged=\(unchanged)\n".utf8))
        return pdf.pageCount > 1 && emptyPages == 0 && unchanged
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

    private func verifySharedPDFJourney() async throws -> Bool {
        let originalBytes = try Data(contentsOf: markdownFile)
        let output = root.appendingPathComponent("shared-layout.pdf")
        var result: Result<Bool, Error>?
        coordinator.exportPDF(to: output) { result = $0 }
        guard await waitUntil(timeout: 8, condition: { self.window.attachedSheet?.title == "Export PDF Layout" }),
              let panel = window.attachedSheet,
              let content = panel.contentView else { return false }
        panel.alphaValue = 0
        let views = descendants(of: content)
        guard let font = views.compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityLabel() == "Font size (pt)" }),
              let citations = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.accessibilityLabel() == "Citations" }),
              let headings = views.compactMap({ $0 as? NSPopUpButton }).first(where: { $0.accessibilityLabel() == "New page before heading" }),
              let export = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Export PDF" }),
              let cancel = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Cancel" }),
              let pageSetup = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Page Setup…" }),
              await waitUntil(timeout: 8, condition: { export.isEnabled }) else { return false }
        let footnotesDefault = citations.titleOfSelectedItem == "Page-bottom footnotes"
        headings.selectItem(withTitle: "Heading 2")
        _ = headings.sendAction(headings.action, to: headings.target)
        guard await waitUntil(timeout: 8, condition: { export.isEnabled }) else { return false }
        let pageCountVisible = descendants(of: content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Preview ready —") && $0.stringValue.contains("pages") }
        pageSetup.performClick(nil)
        guard await waitUntil(timeout: 8, condition: { export.isEnabled }) else { return false }
        font.stringValue = "not a number"
        _ = font.sendAction(font.action, to: font.target)
        let invalidDisabled = !export.isEnabled
        for value in ["14", "16", "18"] {
            font.stringValue = value
            _ = font.sendAction(font.action, to: font.target)
        }
        guard await waitUntil(timeout: 10, condition: { export.isEnabled }) else {
            cancel.performClick(nil)
            return false
        }
        font.stringValue = "20"
        export.performClick(nil)
        guard await waitUntil(timeout: 8, condition: { result != nil }),
              case .success(true)? = result,
              let pdf = PDFDocument(url: output),
              pdf.string?.contains("Recovered After Crash") == true,
              await waitUntil(timeout: 2, condition: { PrintLayoutSession.activeCountForTesting == 0 && PreparedPrintDocument.retainedCountForTesting == 0 }) else { return false }
        let settingsSaved = PrintLayoutSettingsStore(preferences: printPreferences.defaults).load().fontSize == 20
        let printedFontMatches = pdf.page(at: 0)?.attributedString?.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont
        let finalSettingsPrinted = abs((printedFontMatches?.pointSize ?? 0) - 40) < 1
        let selectedPaperPrinted = abs((pdf.page(at: 0)?.bounds(for: .mediaBox).width ?? 0) - 595) < 1
            && abs((pdf.page(at: 0)?.bounds(for: .mediaBox).height ?? 0) - 842) < 1
        let unchangedSource = try Data(contentsOf: markdownFile) == originalBytes
        let citationPrinted = pdf.page(at: 0)?.string?.contains("https://example.com/native-citation") == true
        let authoredPrinted = pdf.page(at: 0)?.string?.contains("NATIVE-AUTHORED-NOTE") == true

        var cancelled: Result<Bool, Error>?
        let cancelledOutput = root.appendingPathComponent("cancelled-layout.pdf")
        coordinator.exportPDF(to: cancelledOutput) { cancelled = $0 }
        guard await waitUntil(timeout: 8, condition: { self.window.attachedSheet?.title == "Export PDF Layout" }),
              let cancelPanel = window.attachedSheet,
              let cancelView = cancelPanel.contentView,
              let cancelButton = descendants(of: cancelView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Cancel" }) else { return false }
        cancelPanel.alphaValue = 0
        cancelButton.performClick(nil)
        guard await waitUntil(timeout: 2, condition: { cancelled != nil }),
              case .success(false)? = cancelled,
              !FileManager.default.fileExists(atPath: cancelledOutput.path) else { return false }

        var closed: Result<Bool, Error>?
        coordinator.exportPDF(to: cancelledOutput) { closed = $0 }
        guard await waitUntil(timeout: 8, condition: { self.window.attachedSheet?.title == "Export PDF Layout" }),
              let closePanel = window.attachedSheet else { return false }
        closePanel.alphaValue = 0
        closePanel.close()
        let closedCancelled = await waitUntil(timeout: 2, condition: {
            if case .success(false)? = closed { return true }
            return false
        })
        var printCancelled = false
        model.telemetryHandler = { event, _ in
            if event == "ouro_md_print_cancelled" { printCancelled = true }
        }
        coordinator.printDocument()
        guard await waitUntil(timeout: 8, condition: { self.window.attachedSheet?.title == "Print Layout" }),
              let printPanel = window.attachedSheet, let printView = printPanel.contentView,
              let continueButton = descendants(of: printView).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Continue to Print" }),
              await waitUntil(timeout: 8, condition: { continueButton.isEnabled }) else { return false }
        printPanel.alphaValue = 0
        continueButton.performClick(nil)
        let finalPrintCancelled = await waitUntil(timeout: 2, condition: { printCancelled && PrintLayoutSession.activeCountForTesting == 0 })
        print("print slice checks: default=\(footnotesDefault) pageCount=\(pageCountVisible) citation=\(citationPrinted) authored=\(authoredPrinted) invalid=\(invalidDisabled) saved=\(settingsSaved) finalFont=\(finalSettingsPrinted) paper=\(selectedPaperPrinted) source=\(unchangedSource) closed=\(closedCancelled) printCancel=\(finalPrintCancelled)")
        return footnotesDefault && pageCountVisible && citationPrinted && authoredPrinted && invalidDisabled && settingsSaved && finalSettingsPrinted && selectedPaperPrinted && unchangedSource && closedCancelled && finalPrintCancelled
            && PrintLayoutSession.activeCountForTesting == 0 && PreparedPrintDocument.retainedCountForTesting == 0
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
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
        printPreferences.remove()
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

    Native [citation](https://example.com/native-citation) and authored note.[^native]

    ## Company Alpha

    First company.

    ## Company Beta

    Second company.

    [^native]: NATIVE-AUTHORED-NOTE
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
