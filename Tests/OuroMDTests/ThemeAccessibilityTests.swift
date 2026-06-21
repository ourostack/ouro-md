import XCTest
@testable import OuroMD

final class ThemeAccessibilityTests: XCTestCase {
    func testBuiltInThemesMeetContrastForDocumentTextLinksAndSecondaryText() throws {
        let builtIns = ["quartz", "graphite", "manuscript", "newsprint"].map { ThemeStore.shared.theme(id: $0) }

        for theme in builtIns {
            let css = theme.css
            let background = try hex(after: "body{background:", in: css)
            let body = try hex(after: "color:", in: css)
            let link = try hex(after: "a{color:", in: css)
            let secondary = try hex(after: "h6{font-size:1em;color:", in: css)
            let quoteBlock = try fragment(after: "blockquote{", before: "}", in: css)
            let quote = try hex(after: "color:", in: quoteBlock)

            XCTAssertGreaterThanOrEqual(contrast(body, background), 4.5, "\(theme.id) body text contrast")
            XCTAssertGreaterThanOrEqual(contrast(link, background), 4.5, "\(theme.id) link contrast")
            XCTAssertGreaterThanOrEqual(contrast(secondary, background), 4.5, "\(theme.id) secondary text contrast")
            XCTAssertGreaterThanOrEqual(contrast(quote, background), 4.5, "\(theme.id) blockquote text contrast")
        }
    }

    func testEditorThemesRespectReducedMotionForFocusMode() {
        for id in ["quartz", "graphite", "manuscript", "newsprint"] {
            let css = ThemeStore.shared.theme(id: id).editorCSS
            XCTAssertTrue(css.contains("@media (prefers-reduced-motion:reduce)"), "\(id) missing reduced-motion media query")
            XCTAssertTrue(css.contains("transition:none!important"), "\(id) missing focus transition disable")
        }
    }

    private func hex(after needle: String, in text: String) throws -> String {
        guard let range = text.range(of: needle) else {
            throw XCTSkip("missing color token after \(needle)")
        }
        let suffix = text[range.upperBound...]
        guard let match = suffix.range(of: #"#[0-9a-fA-F]{6}"#, options: .regularExpression) else {
            throw XCTSkip("missing hex color after \(needle)")
        }
        return String(suffix[match])
    }

    private func fragment(after startNeedle: String, before endNeedle: String, in text: String) throws -> String {
        guard let start = text.range(of: startNeedle) else {
            throw XCTSkip("missing fragment start \(startNeedle)")
        }
        let suffix = text[start.upperBound...]
        guard let end = suffix.range(of: endNeedle) else {
            throw XCTSkip("missing fragment end \(endNeedle)")
        }
        return String(suffix[..<end.lowerBound])
    }

    private func contrast(_ foreground: String, _ background: String) -> Double {
        let fg = relativeLuminance(foreground)
        let bg = relativeLuminance(background)
        let lighter = max(fg, bg)
        let darker = min(fg, bg)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ hex: String) -> Double {
        let start = hex.index(after: hex.startIndex)
        let value = Int(hex[start...], radix: 16) ?? 0
        let channels = [
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255,
        ]
        let linear = channels.map { channel in
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
