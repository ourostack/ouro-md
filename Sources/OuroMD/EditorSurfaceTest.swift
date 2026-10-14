import AppKit
import CryptoKit
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
    private var activationObserver: NSObjectProtocol?
    private let printPreferences = ScratchUserDefaults(label: "print-journey")
    private var acceptanceInput: URL? {
        ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_FILE"].map { URL(fileURLWithPath: $0) }
    }
    var requiresFocusedEditor: Bool { acceptanceInput == nil }
    var activationPolicy: NSApplication.ActivationPolicy { requiresFocusedEditor ? .accessory : .prohibited }
    var printPresentation: PrintLayoutSession.Presentation { requiresFocusedEditor ? .sheet : .headless }

    func run() -> Never {
        let app = NSApplication.shared
        let acceptedPolicy = app.setActivationPolicy(activationPolicy)
        if !requiresFocusedEditor {
            guard acceptedPolicy, !app.isActive else {
                FileHandle.standardError.write(Data("print acceptance could not prohibit application activation\n".utf8))
                exit(1)
            }
            activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: app, queue: .main) { _ in
                FileHandle.standardError.write(Data("print acceptance violated its non-activation policy\n".utf8))
                exit(1)
            }
        }
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
        coordinator.printPresentation = printPresentation
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

        window = requiresFocusedEditor
            ? HeadlessHarness.offscreenHostActive(webView, size: frame.size)
            : HeadlessHarness.nonPresentingHost(webView, size: frame.size)

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
        let environment = ProcessInfo.processInfo.environment
        if let font = environment["OURO_PRINT_ACCEPTANCE_FONT_SIZE"] {
            guard let value = Double(font), (8...23).contains(value) else { throw SurfaceError("Invalid acceptance font size.") }
            settings.fontSize = value
        }
        if let margin = environment["OURO_PRINT_ACCEPTANCE_MARGIN_PT"] {
            guard let value = Double(margin), (18...144).contains(value) else { throw SurfaceError("Invalid acceptance margin.") }
            settings.margins = PrintPageMargins(top: value, right: value, bottom: value, left: value)
        }
        PrintLayoutSettingsStore(preferences: printPreferences.defaults).save(settings)
        if environment["OURO_PRINT_ACCEPTANCE_AUDIT_ONLY"] == "1" {
            guard let pdf = PDFDocument(url: output) else { throw SurfaceError("No captured product PDF is available to audit.") }
            let audit = try await auditLocalPrint(pdf: pdf, settings: settings)
            let unchanged = try Data(contentsOf: markdownFile) == before
            if let path = environment["OURO_PRINT_ACCEPTANCE_REPORT"] {
                let report: [String: Any] = ["auditOnly": true, "inputBytes": before.count, "inputSHA256": Self.sha256(before), "pdfSHA256": Self.sha256(try Data(contentsOf: output)), "pages": pdf.pageCount, "sourceUnchanged": unchanged, "contentAudit": audit]
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            return unchanged && audit["missingWords"] == 0 && audit["missingCells"] == 0 && audit["headingsNotAtPageStart"] == 0 && audit["pagesWithInkOutsideMargins"] == 0
        }
        _ = await evaluate("(function(){var original=window.ouro.getHTML;window.ouro.getHTML=function(){var start=performance.now();try{return original.apply(this,arguments);}finally{window.__ouroAcceptanceHTMLMilliseconds=performance.now()-start;}};})()")
        FileHandle.standardError.write(Data("local print acceptance: requesting product export\n".utf8))
        let trace = PrintPreviewTrace()
        coordinator.onPrintPhase = { trace.record($0) }
        coordinator.profilePrintLayout = true
        defer { coordinator.onPrintPhase = nil; coordinator.profilePrintLayout = false }
        var exported: Bool?
        model.exportPDF(to: output) { exported = $0 }
        guard await waitUntil(timeout: 20, condition: { PrintLayoutSession.activeSession(for: self.window) != nil }),
              let panel = PrintLayoutSession.activeSession(for: window)?.panelForTesting, let view = panel.contentView,
              let button = descendants(of: view).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Export PDF" }),
              let preview = descendants(of: view).compactMap({ $0 as? PDFView }).first,
              let font = descendants(of: view).compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityLabel() == "Font size (pt)" }) else {
            throw SurfaceError("Product print layout did not open for the local document.")
        }
        let preparationViewSeconds = trace.elapsedSeconds
        try verifyNonPresentingWindows(panel: panel)
        guard await waitUntil(timeout: 10, condition: { (preview.document?.pageCount ?? 0) > 0 }) else {
            throw SurfaceError("First print preview page did not appear promptly.")
        }
        let firstPageSeconds = trace.elapsedSeconds
        let progressive = !printPreviewIsReady(in: view)
        let progress = descendants(of: view).compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("Preparing page ") }?.stringValue ?? "Unknown progress"
        FileHandle.standardError.write(Data("local print acceptance: firstPageSeconds=\(firstPageSeconds) \(progress)\n".utf8))
        if let path = environment["OURO_PRINT_ACCEPTANCE_DIAGNOSTICS"] {
            try await capturePrintGeometry(to: path + "-geometry.json")
            if environment["OURO_PRINT_ACCEPTANCE_GEOMETRY_ONLY"] == "1" {
                throw SurfaceError("Private print geometry recorded; output capture not requested.")
            }
        }
        guard await waitUntil(timeout: 60, condition: { self.printPreviewIsReady(in: view) }),
              let initialDocument = preview.document else {
            throw SurfaceError("Full document print preview did not finish.")
        }
        let readySeconds = trace.elapsedSeconds
        let initialPhaseEvents = trace.events
        let initialProfile = try await PrintLayoutSession.activeSession(for: window)?.prepared?.webView.evaluateJavaScript("window.__ouroPrintLayoutProfile")
        let editorFontFamily = await evaluate("(function(){var root=document.querySelector('.vditor-ir .vditor-reset,.vditor-wysiwyg .vditor-reset');return root ? getComputedStyle(root).fontFamily : null;})()") as? String
        let printFontFamily = try await PrintLayoutSession.activeSession(for: window)?.prepared?.webView.evaluateJavaScript("getComputedStyle(document.querySelector('.markdown-body')).fontFamily") as? String
        guard let editorFontFamily, let printFontFamily, editorFontFamily == printFontFamily else {
            throw SurfaceError("The print copy did not inherit the applied editor theme's body font.")
        }
        let initialPages = initialDocument.pageCount
        FileHandle.standardError.write(Data("local print acceptance: readySeconds=\(readySeconds) pages=\(initialPages)\n".utf8))
        let changed = ProcessInfo.processInfo.systemUptime
        font.stringValue = String(settings.fontSize + 1)
        _ = font.sendAction(font.action, to: font.target)
        guard preview.document === initialDocument,
              !self.printPreviewIsReady(in: view),
              await waitUntil(timeout: 60, condition: { self.printPreviewIsReady(in: view) }),
              let changedDocument = preview.document,
              changedDocument !== initialDocument,
              PrintLayoutSession.activeSession(for: window)?.prepared?.settings.fontSize == settings.fontSize + 1 else {
            let status = descendants(of: view).compactMap { $0 as? NSTextField }.filter { !$0.isEditable }.map(\.stringValue).joined(separator: "; ")
            throw SurfaceError("Font-size control did not produce a complete changed layout: \(status)")
        }
        let changedSeconds = ProcessInfo.processInfo.systemUptime - changed
        let changedPages = changedDocument.pageCount
        font.stringValue = String(settings.fontSize)
        _ = font.sendAction(font.action, to: font.target)
        guard await waitUntil(timeout: 60, condition: { self.printPreviewIsReady(in: view) }),
              preview.document?.pageCount == initialPages else {
            throw SurfaceError("Restoring the font size did not restore the complete layout.")
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
        try verifyNonPresentingWindows(panel: panel)
        FileHandle.standardError.write(Data("local print acceptance: bytes=\(before.count) pages=\(pdf.pageCount) emptyPages=\(emptyPages) sourceUnchanged=\(unchanged)\n".utf8))
        let audit = try await auditLocalPrint(pdf: pdf, settings: settings)
        let report: [String: Any] = [
            "inputBytes": before.count, "inputSHA256": Self.sha256(before), "pdfSHA256": Self.sha256(try Data(contentsOf: output)), "fontSize": settings.fontSize, "marginPt": settings.margins.top,
            "preparationViewSeconds": preparationViewSeconds, "firstPageSeconds": firstPageSeconds, "readySeconds": readySeconds,
            "headlessPresentation": true,
            "hostAndPanelCannotTakeFocus": true,
            "printPanelNeverOrdered": !panel.isVisible,
            "hostAlpha": window.alphaValue,
            "firstPageWhilePreparing": progressive, "changedFontReadySeconds": changedSeconds,
            "initialPages": initialPages, "changedFontPages": changedPages, "exportedPages": pdf.pageCount,
            "emptyPages": emptyPages, "sourceUnchanged": unchanged,
            "hostRequiresEditorActivation": requiresFocusedEditor,
            "probeActivationPolicy": NSApplication.shared.activationPolicy().rawValue,
            "probeApplicationActive": NSApplication.shared.isActive,
            "editorHTMLMilliseconds": (await evaluate("window.__ouroAcceptanceHTMLMilliseconds")) as? Double ?? -1,
            "phaseEvents": initialPhaseEvents,
            "layoutProfile": initialProfile ?? [:],
            "themeBodyFontMatchesEditor": true,
            "contentAudit": audit
        ]
        if let path = environment["OURO_PRINT_ACCEPTANCE_REPORT"] {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        return pdf.pageCount == initialPages && emptyPages == 0 && unchanged && progressive && firstPageSeconds < 10 && readySeconds < 60 && changedSeconds < 60 && audit["missingWords"] == 0 && audit["missingCells"] == 0 && audit["headingsNotAtPageStart"] == 0 && audit["pagesWithInkOutsideMargins"] == 0
    }

    private func verifyNonPresentingWindows(panel: NSPanel) throws {
        guard !NSApp.isActive, !panel.isVisible, panel.alphaValue == 0,
              !panel.canBecomeKey, !panel.canBecomeMain, !panel.isKeyWindow, !panel.isMainWindow,
              window.alphaValue == 0, !window.canBecomeKey, !window.canBecomeMain,
              !window.isKeyWindow, !window.isMainWindow, window.attachedSheet == nil else {
            throw SurfaceError("Headless print acceptance attempted window presentation or focus.")
        }
    }

    private func capturePrintGeometry(to path: String) async throws {
        let pattern = EditorWebView.Coordinator.jsString(ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_GEOMETRY_PATTERN"] ?? ".+")
        let inspectVisibility = ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_GEOMETRY_ONLY"] == "1"
        for candidate in NSApplication.shared.windows.flatMap({ $0.contentView.map { descendants(of: $0) } ?? [] }).compactMap({ $0 as? WKWebView }) where candidate !== webView {
            let geometry = try await candidate.evaluateJavaScript("""
            (function(){
              if(!window.OuroPrintLayout){return null;}
              var root=document.querySelector('.markdown-body'),origin=root.getBoundingClientRect(),metrics=window.OuroPrintLayout.metrics(),pattern=new RegExp(\(pattern),"g");
              function rectangles(rects){origin=root.getBoundingClientRect();return Array.from(rects).map(function(r){return {page:Math.floor((r.left-origin.left+.5)/metrics.pageStride)+1,x:(r.left-origin.left)%metrics.pageStride,y:r.top-origin.top,width:r.width,height:r.height};});}
              var walker=document.createTreeWalker(root.parentNode,NodeFilter.SHOW_TEXT),nodes=[],subjects=[],node;
              while((node=walker.nextNode())){
                pattern.lastIndex=0;var match;
                while((match=pattern.exec(node.data))){
                  if(!match[0].length){throw new Error("Geometry pattern must match nonempty text.");}
                  var range=document.createRange();range.setStart(node,match.index);range.setEnd(node,match.index+match[0].length);
                  nodes.push({tag:node.parentElement.tagName,text:match[0],footer:!!node.parentElement.closest('.ouro-print-page-notes'),element:rectangles(node.parentElement.getClientRects()),textRects:rectangles(range.getClientRects())});
                  subjects.push(node.parentElement);
                }
              }
              if(\(inspectVisibility ? "true" : "false")){
                var active=/translateX\\(-?([\\d.]+)px\\)/.exec(root.style.transform),previous=active?Math.round(Number(active[1])/metrics.pageStride):0;
                nodes.forEach(function(record,index){record.visibilityOnTextPages=Array.from(new Set(record.textRects.map(r=>r.page))).map(function(page){window.OuroPrintLayout.showPage(page-1);var element=subjects[index],hidden=[];for(var ancestor=element;ancestor&&ancestor!==root.parentNode;ancestor=ancestor.parentElement){if(getComputedStyle(ancestor).visibility==="hidden"){hidden.push({tag:ancestor.tagName,ownStyle:ancestor.style.visibility,rectangles:rectangles(ancestor.getClientRects())});}}return {page:page,visibility:getComputedStyle(element).visibility,ownStyle:element.style.visibility,hiddenAncestors:hidden};});});
                window.OuroPrintLayout.showPage(previous);
              }
              return {bodyHeight:root.getBoundingClientRect().height,nodes:nodes};
            })()
            """)
            if let geometry {
                try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
                return
            }
        }
        throw SurfaceError("Prepared print web view was not available for geometry diagnostics.")
    }

    static func wrappedCellWordCount(_ word: String, pageTexts: [String], verifiedCells: [String]) throws -> Int {
        guard !word.isEmpty else { return 0 }
        let start = #"(?<![\p{L}\p{N}])"#
        let end = #"(?![\p{L}\p{N}])"#
        let source = try NSRegularExpression(pattern: start + NSRegularExpression.escapedPattern(for: word) + end)
        guard verifiedCells.contains(where: { source.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) else { return 0 }
        let wrapped = try NSRegularExpression(pattern: start + word.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\n?"#) + end)
        return pageTexts.reduce(0) { count, text in
            count + wrapped.matches(in: text, range: NSRange(text.startIndex..., in: text)).filter {
                (text as NSString).substring(with: $0.range).contains("\n")
            }.count
        }
    }

    private func auditLocalPrint(pdf: PDFDocument, settings: PrintLayoutSettings) async throws -> [String: Int] {
        guard let expected = await evaluate("""
        (function(){
          var root = new DOMParser().parseFromString(window.ouro.getHTML(), "text/html");
          root.querySelectorAll("script, style").forEach(function(node){node.remove();});
          root.querySelectorAll("p,li,td,th,div,section,aside,summary,details,h1,h2,h3,h4,h5,h6,br").forEach(function(node){node.appendChild(root.createTextNode(" "));});
          return {
            text: root.body.textContent,
            cells: Array.from(root.querySelectorAll("td, th")).map(function(node){return node.textContent;}),
            headings: Array.from(root.querySelectorAll("h\(settings.headingBreakLevel)")).map(function(node){return node.textContent.trim();})
          };
        })()
        """) as? [String: Any],
              let body = expected["text"] as? String,
              let cells = expected["cells"] as? [String],
              let headings = expected["headings"] as? [String] else {
            throw SurfaceError("Could not collect private document content for print verification.")
        }
        let wordPattern = try NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")
        func words(_ text: String) -> [String] {
            let folded = text.precomposedStringWithCompatibilityMapping
            return wordPattern.matches(in: folded, range: NSRange(folded.startIndex..., in: folded)).map {
                (folded as NSString).substring(with: $0.range)
            }
        }
        func compact(_ text: String) -> String {
            words(text.replacingOccurrences(of: #"\[\s*S\s*[\d\s]+\]"#, with: "", options: .regularExpression)).joined()
        }
        let pageTexts = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
        let footerStart = try NSRegularExpression(pattern: #"\[S\d+\]\s+(?:https?:|file:|mailto:|tel:)"#)
        let actualText = pageTexts.joined(separator: "\n")
        let actualWords = words(actualText).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let expectedWords = words(body).reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let rawMissingWords = expectedWords.reduce(0) { $0 + max(0, $1.value - (actualWords[$1.key] ?? 0)) }
        let actualCompact = compact(actualText) as NSString
        let initiallyMissing = cells.filter { actualCompact.range(of: compact($0)).location == NSNotFound }
        var columnStreams: [NSString] = []
        var columnPageTexts: [String: [String]] = [:]
        for count in [2, 3] {
            for column in 0..<count {
                var fragments: [String] = []
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index) else { continue }
                    let box = page.bounds(for: .mediaBox)
                    let text = pageTexts[index]
                    let footerTop = footerStart.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { page.selection(for: $0.range)?.bounds(for: page).maxY }.max()
                    let bottom = footerTop.map { $0 + 6 } ?? settings.margins.bottom
                    let width = (box.width - settings.margins.left - settings.margins.right) / Double(count)
                    let bounds = CGRect(x: settings.margins.left + Double(column) * width + 2, y: bottom, width: width - 4, height: box.height - settings.margins.top - bottom)
                    fragments.append(page.selection(for: bounds)?.string ?? "")
                }
                columnPageTexts["\(count)-\(column + 1)"] = fragments
                columnStreams.append(compact(fragments.joined(separator: "\n")) as NSString)
            }
        }
        let missing = initiallyMissing.filter { cell in
            let text = compact(cell)
            return !columnStreams.contains { $0.range(of: text).location != NSNotFound }
        }
        let missingCells = missing.count
        let missingCellText = Set(missing.map(compact))
        let verifiedCells = cells.filter { !missingCellText.contains(compact($0)) }
        var verifiedWrappedWords = 0
        for (word, expectedCount) in expectedWords {
            let shortage = max(0, expectedCount - (actualWords[word] ?? 0))
            if shortage > 0 {
                verifiedWrappedWords += min(shortage, try Self.wrappedCellWordCount(word, pageTexts: pageTexts, verifiedCells: verifiedCells))
            }
        }
        let missingWords = rawMissingWords - verifiedWrappedWords
        if let path = ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_DIAGNOSTICS"] {
            let compactPages = pageTexts.map(compact)
            let examplePages = Set(missing.prefix(8).compactMap { cell in
                let normalized = compact(cell)
                return compactPages.firstIndex { $0.contains(String(normalized.prefix(16))) || $0.contains(String(normalized.suffix(25))) }
            }.flatMap { [$0, min($0 + 1, pdf.pageCount - 1)] }).sorted()
            let diagnostics: [String: Any] = [
                "actualWords": actualWords.values.reduce(0, +),
                "cellsMissingBeforeColumnExtraction": initiallyMissing.count,
                "missingCellExamples": Array(missing.prefix(15)),
                "missingCellPages": examplePages.map { index -> [String: Any] in ["page": index + 1, "text": pageTexts[index], "selectedColumns": columnPageTexts.mapValues { $0[index] }] },
                "missingWordExamples": Array(expectedWords.filter { $0.value > (actualWords[$0.key] ?? 0) }.sorted { $0.value > $1.value }.prefix(15).map { record -> [String: Any] in
                    ["word": record.key, "expected": record.value, "actual": actualWords[record.key] ?? 0, "fusedForms": actualWords.filter { $0.key != record.key && $0.key.contains(record.key) }]
                }),
                "pageText": (0..<min(3, pdf.pageCount)).map { pdf.page(at: $0)?.string ?? "" }
            ]
            try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
            if ProcessInfo.processInfo.environment["OURO_PRINT_ACCEPTANCE_DIAGNOSTICS_ONLY"] == "1" {
                throw SurfaceError("Private content diagnostics recorded; full audit not requested.")
            }
        }
        var headingsNotAtPageStart = 0
        for heading in headings {
            let atStart = (0..<pdf.pageCount).contains { index in
                let text = pageTexts[index]
                guard let page = pdf.page(at: index),
                      let range = text.range(of: heading),
                      let selection = page.selection(for: NSRange(range, in: text)) else { return false }
                return selection.bounds(for: page).maxY >= page.bounds(for: .mediaBox).height - settings.margins.top - 60
            }
            if !atStart { headingsNotAtPageStart += 1 }
        }
        var pagesWithInkOutsideMargins = 0
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { throw SurfaceError("Unreadable page in print audit.") }
            let box = page.bounds(for: .mediaBox)
            let width = Int(box.width), height = Int(box.height)
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            let outside = try pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    throw SurfaceError("Could not raster-audit print output.")
                }
                context.setFillColor(NSColor.white.cgColor)
                context.fill(box)
                page.draw(with: .mediaBox, to: context)
                let bytes = buffer.bindMemory(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width where x < Int(settings.margins.left) - 1 || x >= width - Int(settings.margins.right) + 1 || y < Int(settings.margins.bottom) - 1 || y >= height - Int(settings.margins.top) + 1 {
                        let offset = (y * width + x) * 4
                        if bytes[offset] < 220 || bytes[offset + 1] < 220 || bytes[offset + 2] < 220 { return true }
                    }
                }
                return false
            }
            if outside { pagesWithInkOutsideMargins += 1 }
        }
        return ["expectedWords": expectedWords.values.reduce(0, +), "missingWords": missingWords, "rawTokenMissingWords": rawMissingWords, "verifiedCellWrappedWords": verifiedWrappedWords, "tableCells": cells.count, "missingCells": missingCells, "sectionHeadings": headings.count, "headingsNotAtPageStart": headingsNotAtPageStart, "rasterAuditedPages": pdf.pageCount, "pagesWithInkOutsideMargins": pagesWithInkOutsideMargins]
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
        guard let headingScale = await evaluate("(function(){var root=document.querySelector('.vditor-ir .vditor-reset,.vditor-wysiwyg .vditor-reset'),heading=root&&root.querySelector('h1');return heading ? parseFloat(getComputedStyle(heading).fontSize)/parseFloat(getComputedStyle(root).fontSize) : null;})()") as? Double,
              headingScale.isFinite, headingScale > 0 else { throw SurfaceError("The applied theme's heading scale is unavailable.") }
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
              await waitUntil(timeout: 8, condition: { self.printPreviewIsReady(in: content) }) else { return false }
        let footnotesDefault = citations.titleOfSelectedItem == "Page-bottom footnotes"
        headings.selectItem(withTitle: "Heading 2")
        _ = headings.sendAction(headings.action, to: headings.target)
        guard await waitUntil(timeout: 8, condition: { self.printPreviewIsReady(in: content) }) else { return false }
        let pageCountVisible = descendants(of: content).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("Preview ready —") && $0.stringValue.contains("pages") }
        pageSetup.performClick(nil)
        guard await waitUntil(timeout: 8, condition: { self.printPreviewIsReady(in: content) }) else { return false }
        font.stringValue = "not a number"
        _ = font.sendAction(font.action, to: font.target)
        let invalidDisabled = !export.isEnabled
        for value in ["14", "16", "18"] {
            font.stringValue = value
            _ = font.sendAction(font.action, to: font.target)
        }
        guard await waitUntil(timeout: 10, condition: { self.printPreviewIsReady(in: content) }) else {
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
        let finalSettingsPrinted = abs((printedFontMatches?.pointSize ?? 0) - (20 * headingScale)) < 1
        let selectedPaperPrinted = abs((pdf.page(at: 0)?.bounds(for: .mediaBox).width ?? 0) - 595) < 1
            && abs((pdf.page(at: 0)?.bounds(for: .mediaBox).height ?? 0) - 842) < 1
        let unchangedSource = try Data(contentsOf: markdownFile) == originalBytes
        let citationPrinted = pdf.page(at: 0)?.string?.contains("https://example.com/native-citation") == true
        let authoredPrinted = pdf.page(at: 0)?.string?.contains("NATIVE-AUTHORED-NOTE") == true
        let betaPage = (0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("Second company.") == true }
        let commentPage = (0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("NATIVE-COMMENT-BREAK") == true }
        let divPage = (0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("NATIVE-DIV-BREAK") == true }
        let manualBreaksPrinted = betaPage != nil && commentPage == betaPage.map { $0 + 1 } && divPage == commentPage.map { $0 + 1 }

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
              await waitUntil(timeout: 8, condition: { self.printPreviewIsReady(in: printView) }) else { return false }
        printPanel.alphaValue = 0
        continueButton.performClick(nil)
        let finalPrintCancelled = await waitUntil(timeout: 2, condition: { printCancelled && PrintLayoutSession.activeCountForTesting == 0 })
        print("print slice checks: default=\(footnotesDefault) pageCount=\(pageCountVisible) citation=\(citationPrinted) authored=\(authoredPrinted) manualBreaks=\(manualBreaksPrinted) invalid=\(invalidDisabled) saved=\(settingsSaved) finalFont=\(finalSettingsPrinted) paper=\(selectedPaperPrinted) source=\(unchangedSource) closed=\(closedCancelled) printCancel=\(finalPrintCancelled)")
        return footnotesDefault && pageCountVisible && citationPrinted && authoredPrinted && manualBreaksPrinted && invalidDisabled && settingsSaved && finalSettingsPrinted && selectedPaperPrinted && unchangedSource && closedCancelled && finalPrintCancelled
            && PrintLayoutSession.activeCountForTesting == 0 && PreparedPrintDocument.retainedCountForTesting == 0
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func printPreviewIsReady(in root: NSView) -> Bool {
        descendants(of: root).compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("Preview ready —") }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
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

    <!-- pagebreak -->

    ### Manual comment break

    NATIVE-COMMENT-BREAK

    <div class="page-break"></div>

    ### Manual div break

    NATIVE-DIV-BREAK

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
