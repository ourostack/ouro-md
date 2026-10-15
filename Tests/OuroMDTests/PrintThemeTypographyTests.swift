import AppKit
import PDFKit
import XCTest
@testable import OuroMD

enum PrintEmbeddedFontProof {
    struct Font {
        let name: String
        let embedded: Bool
    }

    private final class Collector {
        var fonts: [Font] = []
    }

    static func fonts(in document: PDFDocument) -> [Font] {
        let collector = Collector()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.pageRef, let pageDictionary = page.dictionary else { continue }
            var resources: CGPDFDictionaryRef?
            var fonts: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources,
                  CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { continue }
            CGPDFDictionaryApplyFunction(fonts, { _, object, context in
                guard let context else { return }
                let collector = Unmanaged<Collector>.fromOpaque(context).takeUnretainedValue()
                var dictionary: CGPDFDictionaryRef?
                guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return }
                var name: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(dictionary, "BaseFont", &name), let name else { return }
                var descriptor: CGPDFDictionaryRef?
                if !CGPDFDictionaryGetDictionary(dictionary, "FontDescriptor", &descriptor) {
                    var descendants: CGPDFArrayRef?
                    if CGPDFDictionaryGetArray(dictionary, "DescendantFonts", &descendants), let descendants {
                        var descendant: CGPDFDictionaryRef?
                        if CGPDFArrayGetDictionary(descendants, 0, &descendant), let descendant {
                            _ = CGPDFDictionaryGetDictionary(descendant, "FontDescriptor", &descriptor)
                        }
                    }
                }
                let embedded = descriptor.map { descriptor in
                    ["FontFile", "FontFile2", "FontFile3"].contains { key in
                        var stream: CGPDFStreamRef?
                        return CGPDFDictionaryGetStream(descriptor, key, &stream) && stream != nil
                    }
                } ?? false
                collector.fonts.append(Font(name: String(cString: name), embedded: embedded))
            }, Unmanaged.passUnretained(collector).toOpaque())
        }
        return collector.fonts
    }
}

@MainActor
final class PrintThemeTypographyTests: XCTestCase {
    func testIRThemeDoesNotPickUpWysiwygOnlyFontOverrides() async throws {
        for (mode, family) in [(PrintThemeTypography.EditorMode.ir, "Georgia"), (.wysiwyg, "Helvetica")] {
            let typography = PrintThemeTypography(css: ".vditor-ir .vditor-reset{font-family:Georgia;} .vditor-wysiwyg .vditor-reset{font-family:'Helvetica Neue';}", editorMode: mode)
            let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>MODE-SCOPED-FONT-TOKEN</p>", title: "Mode-scoped typography", baseURL: nil, settings: .default, typography: typography)
            defer { prepared.releaseHold() }
            let data = try await prepared.createPDFData()
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertTrue(try font(for: "MODE-SCOPED-FONT-TOKEN", in: pdf).familyName?.contains(family) == true)
        }
    }

    func testThemeVariablesAndMixedRelativeSizesScaleWithThePrintedBody() async throws {
        let typography = PrintThemeTypography(css: """
        .vditor-reset { font: 20px/2 Georgia; --heading-size: 40px; }
        .vditor-reset h1 { font-size: var(--heading-size); }
        .vditor-reset code { font-family: Menlo; font-size: calc(1em - 2px); }
        """)
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<h1>Variable heading</h1><p>Body <code>Mixed code size</code></p>", title: "Theme variables", baseURL: nil, settings: .default, typography: typography)
        defer { prepared.releaseHold() }
        let sizes = try await prepared.webView.evaluateJavaScript("Array.from(document.querySelectorAll('.markdown-body,h1,code')).map(node=>parseFloat(getComputedStyle(node).fontSize))") as? [Double]
        let values = try XCTUnwrap(sizes)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0], 12, accuracy: 0.01)
        XCTAssertEqual(values[1], 24, accuracy: 0.01)
        XCTAssertEqual(values[2], 10.8, accuracy: 0.01)
    }

    func testThemeTypeHierarchyUsesPrintSizeWithoutImportingThemePageGeometryOrColors() async throws {
        let css = """
        :root { --document-font: "Helvetica Neue"; }
        .vditor-reset { font-family: var(--document-font) !important; font-size: 20px !important; line-height: 2 !important; width: 10px !important; padding: 200px !important; color: white !important; background: black !important; display: none !important; }
        .vditor-reset h1 { font-family: Georgia; font-size: 40px; font-weight: 700; }
        .vditor-reset code { font-family: Menlo; font-size: 18px; }
        .vditor-reset th { font-family: Courier; font-size: 16px; font-weight: 700; }
        """
        let typography = PrintThemeTypography(css: css)
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<h1>THEME-HEADING-TOKEN</h1><p>THEME-BODY-TOKEN <code>THEME-CODE-TOKEN</code></p><table><thead><tr><th>THEME-TABLE-TOKEN</th></tr></thead><tbody><tr><td>Complete themed table</td></tr></tbody></table>",
            title: "Theme typography", baseURL: nil, settings: .default, typography: typography
        )
        defer { prepared.releaseHold() }
        let styles = try await prepared.webView.evaluateJavaScript("""
        (function(){var root=document.querySelector('.markdown-body'),style=getComputedStyle(root);return {width:root.getBoundingClientRect().width,padding:style.paddingLeft,color:style.color,display:style.display,bodySize:parseFloat(style.fontSize),headingSize:parseFloat(getComputedStyle(root.querySelector('h1')).fontSize),codeSize:parseFloat(getComputedStyle(root.querySelector('code')).fontSize),tableSize:parseFloat(getComputedStyle(root.querySelector('th')).fontSize),lineHeight:parseFloat(style.lineHeight)};})()
        """) as? [String: Any]
        XCTAssertEqual(try XCTUnwrap(styles?["width"] as? Double), 504, accuracy: 1)
        XCTAssertEqual(styles?["padding"] as? String, "0px")
        XCTAssertEqual(styles?["color"] as? String, "rgb(17, 17, 17)")
        XCTAssertNotEqual(styles?["display"] as? String, "none")
        XCTAssertEqual(try XCTUnwrap(styles?["bodySize"] as? Double), 12, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(styles?["headingSize"] as? Double), 24, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(styles?["codeSize"] as? Double), 10.8, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(styles?["tableSize"] as? Double), 9.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(styles?["lineHeight"] as? Double), 12 * PrintLayoutSettings.default.lineSpacing, accuracy: 0.01)
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(try font(for: "THEME-BODY-TOKEN", in: pdf).familyName?.contains("Helvetica") == true)
        XCTAssertTrue(try font(for: "THEME-HEADING-TOKEN", in: pdf).familyName?.contains("Georgia") == true)
        XCTAssertTrue(try font(for: "THEME-CODE-TOKEN", in: pdf).familyName?.contains("Menlo") == true)
        XCTAssertTrue(try font(for: "THEME-TABLE-TOKEN", in: pdf).familyName?.contains("Courier") == true)
        XCTAssertEqual(try font(for: "THEME-BODY-TOKEN", in: pdf).pointSize, 12, accuracy: 0.1)
        XCTAssertEqual(try font(for: "THEME-HEADING-TOKEN", in: pdf).pointSize, 24, accuracy: 0.1)
    }

    func testBuiltInThemePrintsBundledOpenSansAndKeepsPaperWhite() async throws {
        let theme = ThemeStore.shared.theme(id: "graphite")
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<h1>Bundled heading</h1><p>BUNDLED-FONT-TOKEN <strong>BUNDLED-BOLD-TOKEN</strong> <em>BUNDLED-ITALIC-TOKEN</em></p>",
            title: "Bundled theme font", baseURL: nil, settings: .default,
            typography: try PrintThemeTypography(theme: theme)
        )
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let webFonts = try await prepared.webView.evaluateJavaScript("Array.from(document.fonts).map(font=>[font.family,font.weight,font.style,font.status])")
        let embeddedFonts = PrintEmbeddedFontProof.fonts(in: pdf)
        let bundledFonts = embeddedFonts.filter { $0.name.replacingOccurrences(of: " ", with: "").contains("OpenSans") && $0.embedded }
        XCTAssertGreaterThanOrEqual(Set(bundledFonts.map(\.name)).count, 3, "Regular, bold and italic theme fonts must be embedded in the PDF resources. Actual fonts: \(embeddedFonts); web fonts: \(String(describing: webFonts)).")
        for token in ["BUNDLED-FONT-TOKEN", "BUNDLED-BOLD-TOKEN", "BUNDLED-ITALIC-TOKEN"] {
            XCTAssertTrue(pdf.string?.contains(token) == true)
        }
        let color = try await prepared.webView.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
        XCTAssertEqual(color, "rgb(255, 255, 255)")
        XCTAssertEqual(try font(for: "BUNDLED-FONT-TOKEN", in: pdf).pointSize, 12, accuracy: 0.1)
    }

    func testThemePayloadCannotCloseTheConfigurationScript() async throws {
        let typography = PrintThemeTypography(css: ".vditor-reset{font-family:'</script><script>window.__ouroFontPayloadExecuted=true</script>';}")
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>SAFE-THEME-PAYLOAD-TOKEN</p>", title: "Escaped typography", baseURL: nil, settings: .default, typography: typography)
        defer { prepared.releaseHold() }
        let executed = try await prepared.webView.evaluateJavaScript("window.__ouroFontPayloadExecuted === true") as? Bool
        XCTAssertEqual(executed, false)
        let data = try await prepared.createPDFData()
        XCTAssertTrue(PDFDocument(data: data)?.string?.contains("SAFE-THEME-PAYLOAD-TOKEN") == true)
    }

    func testBundledThemePDFPreservesLigatureWordsForSearchAndCopy() async throws {
        let text = "Qualification fixture office affinity efficient shuffled workflow"
        let prepared = try await PrintDocumentRenderer().prepareDocument(
            bodyHTML: "<h2>\(text)</h2><p>\(text) <strong>\(text)</strong> <em>\(text)</em></p><table><tr><td>\(text)</td></tr></table>",
            title: "Searchable theme text", baseURL: nil, settings: .default,
            typography: try PrintThemeTypography(theme: ThemeStore.shared.theme(id: "graphite"))
        )
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        for word in text.split(separator: " ") {
            XCTAssertEqual(pdf.string?.components(separatedBy: String(word)).count, 6, "Every heading, body, bold, italic and table occurrence must remain searchable: \(pdf.string ?? "")")
        }
    }

    func testThemeCannotReenableBrokenPDFLigatures() async throws {
        let bundled = try PrintThemeTypography(theme: ThemeStore.shared.theme(id: "graphite"))
        let typography = PrintThemeTypography(css: bundled.css + """
        .vditor-ir .vditor-reset, .vditor-ir .vditor-reset * {
          font-variant-ligatures: common-ligatures !important;
          font-feature-settings: "liga" 1, "clig" 1, "dlig" 1 !important;
        }
        """, fontCSS: bundled.fontCSS, baseURL: bundled.baseURL)
        let text = "Qualification fixture office workflow"
        let prepared = try await PrintDocumentRenderer().prepareDocument(bodyHTML: "<p>\(text)</p>", title: "Theme ligature safety", baseURL: nil, settings: .default, typography: typography)
        defer { prepared.releaseHold() }
        let data = try await prepared.createPDFData()
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertTrue(pdf.string?.contains(text) == true, "Theme declarations must not corrupt searchable print text: \(pdf.string ?? "")")
    }

    private func font(for token: String, in document: PDFDocument) throws -> NSFont {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string, let range = text.range(of: token) else { continue }
            let selection = try XCTUnwrap(page.selection(for: NSRange(range, in: text)))
            return try XCTUnwrap(selection.attributedString?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        }
        throw NSError(domain: "PrintThemeTypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "The complete PDF did not contain \(token)."])
    }
}
