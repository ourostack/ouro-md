import XCTest
@testable import OuroMD

final class TableLayoutPolicyTests: XCTestCase {
    func testStandaloneThemeLetsTablesUseViewportWithTableLocalScroll() {
        let css = ThemeStore.shared.defaultTheme.css

        XCTAssertTrue(css.contains(".markdown-body{max-width:860px;"))
        XCTAssertTrue(css.contains("--ouro-table-viewport:calc(100vw - 24px);"))
        XCTAssertTrue(css.contains("table{border-collapse:collapse;display:block;overflow-x:auto;"))
        XCTAssertTrue(css.contains("width:max-content;min-width:100%;max-width:var(--ouro-table-viewport);"))
        XCTAssertTrue(css.contains("margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2));"))
        XCTAssertTrue(css.contains("th:has(code),td:has(code){max-width:none;}"))
        XCTAssertTrue(css.contains("td code,th code{white-space:nowrap;"))
        XCTAssertFalse(css.contains("word-break:break-word"))
    }

    func testEditorThemeUsesSameTablePolicyAsStandaloneRender() {
        let css = ThemeStore.shared.defaultTheme.editorCSS

        XCTAssertTrue(css.contains(".vditor-reset{color:"))
        XCTAssertTrue(css.contains("--ouro-table-viewport:calc(100vw - 24px);"))
        XCTAssertTrue(css.contains(".vditor{overflow:visible!important;}"))
        XCTAssertTrue(css.contains("overflow:visible!important;--ouro-table-viewport"))
        XCTAssertTrue(css.contains(".vditor-reset table{border-collapse:collapse!important;display:block!important;overflow-x:auto!important;"))
        XCTAssertTrue(css.contains("width:max-content!important;min-width:100%!important;max-width:var(--ouro-table-viewport)!important;"))
        XCTAssertTrue(css.contains("margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2))!important;"))
        XCTAssertTrue(css.contains(".vditor-reset table th:has(code),.vditor-reset table td:has(code){max-width:none!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table td code,.vditor-reset table th code{white-space:nowrap!important;"))
        XCTAssertFalse(css.contains("word-break:break-word"))
    }
}
