import AppKit
import CryptoKit
import PDFKit
import WebKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintPreviewPerformanceTests: XCTestCase {
    func testTableSplittingMovesEachBodyRowOnceAfterMeasuringAllTables() async throws {
        let script = try XCTUnwrap(PrintLayoutScriptLoader.load()) + """
        ;(function(){var apply=window.OuroPrintLayout.apply;window.OuroPrintLayout.apply=function(){window.__ouroOriginalBodyRows=Array.from(document.querySelectorAll('tbody>tr'));return apply();};})();
        """
        let rows = (1...100).map { "<tr><td id=\"retained-row-\($0)\">RETAINED-ROW-\($0)-TOKEN</td><td>Readable table evidence.</td></tr>" }.joined()
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script }).prepareDocument(bodyHTML: "<table><thead><tr><th>Field</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody></table>", title: "Retained rows", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let rowsRetained = try await prepared.webView.evaluateJavaScript("window.__ouroOriginalBodyRows.every(function(row){return row.isConnected;})") as? Bool
        XCTAssertEqual(rowsRetained, true, "Splitting must move measured body rows, not allocate deep copies that immediately replace them.")
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try XCTUnwrap(pdf.string).replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for index in 1...100 {
            XCTAssertEqual(text.components(separatedBy: "RETAINED-ROW-\(index)-TOKEN").count - 1, 1)
        }
    }

    func testOptInLayoutProfileHasOnlyFixedNumericMetadata() async throws {
        let prepared = try await PrintDocumentRenderer(profileLayout: true).prepareDocument(
            bodyHTML: "<p>Profile source <a href=\"https://example.com/source\">source</a></p>",
            title: "Profile metadata", baseURL: nil, settings: .default
        )
        defer { prepared.releaseHold() }
        let result = try await prepared.webView.evaluateJavaScript("window.__ouroPrintLayoutProfile")
        let profile = try XCTUnwrap(result as? [String: Any])
        let steps = try XCTUnwrap(profile["steps"] as? [String: Double])
        XCTAssertNotNil(steps["geometry"])
        XCTAssertNotNil(steps["split_tables"])
        XCTAssertTrue(steps.values.allSatisfy { $0 >= 0 })
        XCTAssertGreaterThan(try XCTUnwrap(profile["rectReads"] as? Int), 0)
        let unprofiled = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>Normal output</p>", title: "Normal", baseURL: nil, settings: .default)
        defer { unprofiled.releaseHold() }
        let disabled = try await unprofiled.webView.evaluateJavaScript("typeof window.__ouroPrintLayoutProfile === 'undefined'") as? Bool
        XCTAssertEqual(disabled, true)
    }

    func testCompanyFieldHeadingsSurviveEveryPageBoundaryInCitedTables() async throws {
        let source = "https://example.com/" + String(repeating: "source-segment/", count: 120)
        let note = String(repeating: "Captured evidence remains readable and complete. ", count: 25)
        let sections = (1...40).map { section -> String in
            let rows = (1...(6 + (section * 13) % 25)).map { row in "<tr><td>FIELD-\(section)-ROW-\(row)</td><td>Readable captured evidence for this field in a normal two-column table.</td></tr>" }.joined()
            let prose = String(repeating: "Readable captured context. ", count: 10 + (section * 19) % 70)
            return "<h2>Company \(section)</h2><details><summary>Captured record</summary><p>\(prose) <a href=\"\(source)\">source</a> <a href=\"#fn-reserved\">1</a></p><p><strong>ORGANIZATION-\(section)-TOKEN</strong></p><table><thead><tr><th>Field</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody></table><p><strong>CHALLENGER-\(section)-TOKEN</strong></p><p>\(prose)</p></details>"
        }.joined()
        var settings = PrintLayoutSettings.default
        settings.fontSize = 9
        settings.margins = PrintPageMargins(top: 20, right: 20, bottom: 20, left: 20)
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: sections + "<section class=\"footnotes\"><ol><li id=\"fn-reserved\">\(note)</li></ol></section>", title: "Field heading boundaries", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (pdf.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for section in 1...40 {
            for prefix in ["ORGANIZATION", "CHALLENGER"] {
                let token = "\(prefix)-\(section)-TOKEN"
                XCTAssertEqual(text.components(separatedBy: token).count - 1, 1, "No field heading may disappear at a page boundary: \(token)")
            }
        }
    }

    func testViewportClippingKeepsEachBodyTokenOnceWithoutVisibilityChanges() async throws {
        let rows = (1...100).map { "<tr><td>CLIPPED-ROW-\($0)-TOKEN</td><td>Readable captured evidence spans columns and has a <a href=\"https://example.com/source\">source</a>.</td></tr>" }.joined()
        let paragraphs = (1...200).map { "<p><strong>CLIPPED-PASSAGE-\($0)-TOKEN</strong> preserves every passage across page boundaries.</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<table><thead><tr><th>Row</th><th>Evidence</th></tr></thead><tbody>\(rows)</tbody></table>\(paragraphs)", title: "Stable viewport clipping", baseURL: nil, settings: .default)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = (pdf.string ?? "").replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        for token in (1...100).map({ "CLIPPED-ROW-\($0)-TOKEN" }) + (1...200).map({ "CLIPPED-PASSAGE-\($0)-TOKEN" }) {
            XCTAssertEqual(text.components(separatedBy: token).count - 1, 1, "Viewport clipping must omit off-page text and preserve the current page: \(token)")
        }
    }

    func testPageActivationDoesNotInvalidateInheritedDocumentStyles() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h2>First section</h2><p>FIRST-PASSAGE</p><h2>Second section</h2><p>SECOND-PASSAGE</p>", title: "Scoped page activation", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        XCTAssertEqual(prepared.layoutMetrics.pageCount, 2)
        let unchanged = try await prepared.webView.evaluateJavaScript("(function(){var inherited=document.documentElement.style.cssText;window.OuroPrintLayout.showPage(1);return inherited===document.documentElement.style.cssText;})()") as? Bool
        XCTAssertEqual(unchanged, true, "Paging must change only page transforms, not inherited styles across the entire document")
    }

    func testPageActivationDoesNotRemeasureAllDocumentLinks() async throws {
        let body = (1...120).map {
            "<p>Passage \($0) retains its source <a href=\"https://example.com/source/\($0)\">reference \($0)</a> while flowing through several pages of readable body text.</p>"
        }.joined()
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        let prepared = try await PrintDocumentRenderer(scriptProvider: Self.profiledScript).prepareDocument(bodyHTML: body, title: "Page activation", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        XCTAssertGreaterThan(prepared.layoutMetrics.pageCount, 3)
        _ = try await prepared.webView.evaluateJavaScript("window.__ouroPrintProfile.anchorRectReads = 0;")
        var observedURLs = Set<String>()
        for index in 0..<prepared.layoutMetrics.pageCount {
            let result = try await prepared.webView.evaluateJavaScript("window.OuroPrintLayout.showPage(\(index))") as? [String: Any]
            let links = try XCTUnwrap(result?["links"] as? [[String: Any]])
            observedURLs.formUnion(links.compactMap { $0["url"] as? String })
        }
        let reads = try await prepared.webView.evaluateJavaScript("window.__ouroPrintProfile.anchorRectReads") as? Int
        XCTAssertEqual(reads, 0, "Activating pages must use layout's cached link geometry, not remeasure every document link on every page")
        XCTAssertEqual(observedURLs, Set((1...120).map { "https://example.com/source/\($0)" }))
    }

    func testManyPageCaptureDoesNotPayAFixedDelayPerPage() async throws {
        var settings = PrintLayoutSettings.default
        settings.citationMode = .originalLinks
        settings.headingBreakLevel = 2
        let body = (1...200).map { "<h2>Page \($0)</h2><p>PAGE-\($0)-CAPTURE-TOKEN</p>" }.joined()
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: body, title: "Responsive capture", baseURL: nil, settings: settings)
        defer { prepared.releaseHold() }
        XCTAssertEqual(prepared.layoutMetrics.pageCount, 200)
        let started = Date()
        let data = try await prepared.createPDFData()
        let elapsed = Date().timeIntervalSince(started)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 200)
        for index in 0..<200 {
            XCTAssertTrue(pdf.page(at: index)?.string?.contains("PAGE-\(index + 1)-CAPTURE-TOKEN") == true, "Captures must use each current page, not the previous painted page")
        }
        XCTAssertLessThan(elapsed, 6, "A fixed paint sleep compounds into a minute of avoidable waiting on large guides")
    }

    func testProfileRequestedPrivateDocument() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["OURO_PRINT_PROFILE_FILE"],
              let reportPath = environment["OURO_PRINT_PROFILE_REPORT"] else {
            throw XCTSkip("Private print profiling requires explicit local input and metadata-report paths.")
        }
        let input = URL(fileURLWithPath: inputPath)
        let before = try Data(contentsOf: input)
        let markdown = try XCTUnwrap(String(data: before, encoding: .utf8))
        let start = Date()
        let body = MarkdownRenderer.renderHTMLBody(markdown, baseDirectory: input.deletingLastPathComponent())
        let markdownMilliseconds = Date().timeIntervalSince(start) * 1_000
        print("private print profile: parsed bytes=\(before.count) bodyBytes=\(body.utf8.count) parseMs=\(Int(markdownMilliseconds))")
        var settings = PrintLayoutSettings.default
        settings.fontSize = try XCTUnwrap(Double(environment["OURO_PRINT_PROFILE_FONT_SIZE"] ?? "9"))
        if let marginText = environment["OURO_PRINT_PROFILE_MARGIN_PT"] {
            let margin = try XCTUnwrap(Double(marginText))
            settings.margins = PrintPageMargins(top: margin, right: margin, bottom: margin, left: margin)
        }
        settings.citationMode = try XCTUnwrap(PrintLayoutSettings.CitationMode(rawValue: try XCTUnwrap(Int(environment["OURO_PRINT_PROFILE_CITATIONS"] ?? "0"))))
        settings.headingBreakLevel = try XCTUnwrap(Int(environment["OURO_PRINT_PROFILE_HEADING_LEVEL"] ?? "0"))
        let script: String
        if let path = environment["OURO_PRINT_PROFILE_SCRIPT_FILE"] {
            script = try String(contentsOfFile: path, encoding: .utf8)
        } else {
            script = try XCTUnwrap(PrintLayoutScriptLoader.load())
        }
        let transformProbe = environment["OURO_PRINT_PROFILE_DIRECT_TRANSFORM"] == "1" ? Self.directTransformProbe : ""
        let prepareStart = Date()
        let prepared = try await PrintDocumentRenderer(scriptProvider: { script + Self.instrumentation + transformProbe }).prepareDocument(bodyHTML: body, title: "Private print profile", baseURL: input.deletingLastPathComponent(), settings: settings)
        defer { prepared.releaseHold() }
        let prepareMilliseconds = Date().timeIntervalSince(prepareStart) * 1_000
        let count = prepared.layoutMetrics.pageCount
        print("private print profile: prepared pages=\(count) prepareMs=\(Int(prepareMilliseconds))")
        if environment["OURO_PRINT_PROFILE_LAYOUT_ONLY"] == "1" {
            let geometry = try await prepared.webView.evaluateJavaScript("""
            (function(){
              var root=document.querySelector('.markdown-body');
              var footers=Array.from(document.querySelectorAll('.ouro-print-page-notes'));
              return {
                bodyHeight:root.getBoundingClientRect().height,
                fullContentHeight:window.__ouroPrintLayoutConfig.pageContentHeight,
                tables:root.querySelectorAll('table').length,
                rows:root.querySelectorAll('tr').length,
                disclosureCount:root.querySelectorAll('details').length,
                footerCount:footers.length,
                maxFooterHeight:Math.max(0,...footers.map(n=>n.getBoundingClientRect().height)),
                columnHistogram:Array.from(root.querySelectorAll('table')).reduce(function(counts,table){var count=table.querySelector('tr').children.length;counts[count]=(counts[count]||0)+1;return counts;},{}),
                cellLengthHistogram:Array.from(root.querySelectorAll('td')).reduce(function(counts,cell){var length=cell.textContent.length;var bucket=length<100?"short":length<500?"medium":length<2000?"long":"huge";counts[bucket]=(counts[bucket]||0)+1;return counts;},{}),
                oversizedRows:Array.from(root.querySelectorAll('tr')).filter(n=>n.getBoundingClientRect().height>window.__ouroPrintLayoutConfig.pageContentHeight).length
              };
            })()
            """)
            let report: [String: Any] = ["inputBytes": before.count, "pages": count, "prepareMilliseconds": prepareMilliseconds, "geometry": try XCTUnwrap(geometry)]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: reportPath), options: .atomic)
            return
        }
        let pdfStart = Date()
        let pdf = try await prepared.createPDFData()
        let pdfMilliseconds = Date().timeIntervalSince(pdfStart) * 1_000
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(document.pageCount, count)
        let profileResult = try await prepared.webView.evaluateJavaScript("window.__ouroPrintProfile")
        let shapeResult = try await prepared.webView.evaluateJavaScript("(function(){var root=document.querySelector('.markdown-body');return {nodes:root.querySelectorAll('*').length,anchors:root.querySelectorAll('a[href]').length,tables:root.querySelectorAll('table').length,rows:root.querySelectorAll('tr').length,images:root.querySelectorAll('img').length};})()")
        let profile = try XCTUnwrap(profileResult as? [String: Any])
        let shape = try XCTUnwrap(shapeResult as? [String: Any])
        let samples = try await snapshotSamples(prepared: prepared, pageCount: count)
        let report: [String: Any] = [
            "inputBytes": before.count,
            "inputSHA256": SHA256.hash(data: before).map { String(format: "%02x", $0) }.joined(),
            "bodyHTMLBytes": body.utf8.count,
            "fontSize": settings.fontSize,
            "marginPoints": settings.margins.top,
            "prePaginationTables": body.components(separatedBy: "<table").count - 1,
            "citationMode": settings.effectiveCitationMode.rawValue,
            "headingBreakLevel": settings.headingBreakLevel,
            "pages": count,
            "markdownMilliseconds": markdownMilliseconds,
            "prepareMilliseconds": prepareMilliseconds,
            "pdfMilliseconds": pdfMilliseconds,
            "pdfBytes": pdf.count,
            "javascript": profile,
            "shape": shape,
            "pageSamples": samples
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: reportPath), options: .atomic)
        XCTAssertEqual(try Data(contentsOf: input), before)
        print("private print profile: bytes=\(before.count) pages=\(count) prepareMs=\(Int(prepareMilliseconds)) pdfMs=\(Int(pdfMilliseconds))")
    }

    private func snapshotSamples(prepared: PreparedPrintDocument, pageCount: Int) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        for index in Set([0, pageCount / 2, max(0, pageCount - 1)]).sorted() {
            let activationStart = Date()
            _ = try await prepared.webView.evaluateJavaScript("window.OuroPrintLayout.showPage(\(index))")
            let activationMilliseconds = Date().timeIntervalSince(activationStart) * 1_000
            let configuration = WKPDFConfiguration()
            configuration.rect = prepared.webView.bounds
            let snapshotStart = Date()
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                prepared.webView.createPDF(configuration: configuration) { continuation.resume(with: $0) }
            }
            results.append(["page": index, "activationMilliseconds": activationMilliseconds, "snapshotMilliseconds": Date().timeIntervalSince(snapshotStart) * 1_000, "bytes": data.count])
        }
        return results
    }

    private static func profiledScript() -> String {
        (PrintLayoutScriptLoader.load() ?? "") + instrumentation
    }

    private static let instrumentation = """
    (function(){
      var profile = window.__ouroPrintProfile = {applyMilliseconds: 0, pageMilliseconds: [], anchorRectReads: 0};
      var rects = Element.prototype.getClientRects;
      Element.prototype.getClientRects = function(){
        if (this.tagName.toLowerCase() === "a") { profile.anchorRectReads += 1; }
        return rects.call(this);
      };
      var apply = window.OuroPrintLayout.apply;
      window.OuroPrintLayout.apply = function(){
        var start = performance.now();
        try { return apply.apply(this, arguments); } finally { profile.applyMilliseconds += performance.now() - start; }
      };
      var show = window.OuroPrintLayout.showPage;
      window.OuroPrintLayout.showPage = function(){
        var start = performance.now();
        try { return show.apply(this, arguments); } finally { profile.pageMilliseconds.push(performance.now() - start); }
      };
    })();
    """

    private static let directTransformProbe = """
    (function(){
      var setProperty = CSSStyleDeclaration.prototype.setProperty;
      CSSStyleDeclaration.prototype.setProperty = function(name, value, priority){
        if (this === document.documentElement.style && name === "--ouro-active-page-offset") {
          var transform = "translateX(-" + value + ")";
          var root = document.querySelector(".markdown-body");
          if (root) { root.style.transform = transform; }
          document.querySelectorAll(".ouro-print-page-notes").forEach(function(note){ note.style.transform = transform; });
          return;
        }
        return setProperty.call(this, name, value, priority);
      };
    })();
    """
}
