import XCTest
@testable import OuroMD

final class TableLayoutPolicyTests: XCTestCase {
    func testStandaloneThemeLetsTablesUseViewportWithTableLocalScroll() {
        let css = ThemeStore.shared.defaultTheme.css

        XCTAssertTrue(css.contains(".markdown-body{max-width:860px;"))
        XCTAssertTrue(css.contains("--ouro-table-viewport:calc(100vw - 24px);"))
        XCTAssertTrue(css.contains("table{border-collapse:collapse;display:block;overflow-x:auto;"))
        XCTAssertTrue(css.contains("width:max-content;min-width:100%;max-width:var(--ouro-table-viewport);"))
        XCTAssertTrue(css.contains("table tr{border:1px solid"))
        XCTAssertTrue(css.contains("margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2));"))
        XCTAssertTrue(css.contains("th.ouro-code-only-cell,td.ouro-code-only-cell{min-width:max-content;max-width:none;}"))
        XCTAssertTrue(css.contains("td code,th code{white-space:nowrap;display:inline-block;max-width:100%;overflow-x:auto;"))
        XCTAssertFalse(css.contains("display:grid;grid-template-columns"))
        XCTAssertFalse(css.contains("display:contents"))
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
        XCTAssertTrue(css.contains(".vditor-reset table tr{border:1px solid"))
        XCTAssertTrue(css.contains("margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2))!important;"))
        XCTAssertTrue(css.contains(".vditor-reset table th.ouro-code-only-cell,.vditor-reset table td.ouro-code-only-cell{min-width:max-content!important;max-width:none!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table td code,.vditor-reset table th code{white-space:nowrap!important;display:inline-block!important;max-width:100%!important;overflow-x:auto!important;"))
        XCTAssertFalse(css.contains("display:grid!important;grid-template-columns"))
        XCTAssertFalse(css.contains("display:contents!important"))
        XCTAssertFalse(css.contains("word-break:break-word"))
    }
}
