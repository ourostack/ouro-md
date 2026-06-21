import XCTest
@testable import OuroMD

final class TableLayoutPolicyTests: XCTestCase {
    func testStandaloneThemeLetsTablesUseViewportWithTableLocalScroll() {
        let css = ThemeStore.shared.defaultTheme.css

        XCTAssertTrue(css.contains(".markdown-body{max-width:860px;"))
        XCTAssertTrue(css.contains("--ouro-table-viewport:calc(100vw - 24px);"))
        XCTAssertTrue(css.contains("table{border-collapse:collapse;display:block;overflow-x:auto;"))
        XCTAssertTrue(css.contains("width:max-content;min-width:100%;max-width:var(--ouro-table-viewport);"))
        XCTAssertTrue(css.contains("table:has(tr>:nth-child(2):last-child){display:grid;grid-template-columns:repeat(2,minmax(18rem,1fr));width:var(--ouro-table-viewport);}"))
        XCTAssertTrue(css.contains("table:has(tr>:nth-child(3):last-child){display:grid;grid-template-columns:repeat(3,minmax(16rem,1fr));width:var(--ouro-table-viewport);}"))
        XCTAssertTrue(css.contains("table:has(tr>:nth-child(4):last-child){display:grid;grid-template-columns:repeat(4,minmax(14rem,1fr));width:var(--ouro-table-viewport);}"))
        XCTAssertTrue(css.contains("thead,table:has(tr>:nth-child(2):last-child) tbody,table:has(tr>:nth-child(2):last-child) tr"))
        XCTAssertTrue(css.contains("table:has(tr>:nth-child(2):last-child) th,table:has(tr>:nth-child(3):last-child) th,table:has(tr>:nth-child(4):last-child) th{background:"))
        XCTAssertTrue(css.contains("border-left:1px solid"))
        XCTAssertTrue(css.contains("td{border-top:0;border-right:1px solid"))
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
        XCTAssertTrue(css.contains(".vditor-reset table:has(tr>:nth-child(2):last-child){display:grid!important;grid-template-columns:repeat(2,minmax(18rem,1fr));width:var(--ouro-table-viewport)!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table:has(tr>:nth-child(3):last-child){display:grid!important;grid-template-columns:repeat(3,minmax(16rem,1fr));width:var(--ouro-table-viewport)!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table:has(tr>:nth-child(4):last-child){display:grid!important;grid-template-columns:repeat(4,minmax(14rem,1fr));width:var(--ouro-table-viewport)!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table:has(tr>:nth-child(2):last-child) thead,.vditor-reset table:has(tr>:nth-child(2):last-child) tbody"))
        XCTAssertTrue(css.contains(".vditor-reset table:has(tr>:nth-child(2):last-child) th,.vditor-reset table:has(tr>:nth-child(3):last-child) th,.vditor-reset table:has(tr>:nth-child(4):last-child) th{background:"))
        XCTAssertTrue(css.contains("border-left:1px solid"))
        XCTAssertTrue(css.contains("td{border-top:0!important;border-right:1px solid"))
        XCTAssertTrue(css.contains("margin-left:min(0px, calc((100% - var(--ouro-table-viewport)) / 2))!important;"))
        XCTAssertTrue(css.contains(".vditor-reset table th:has(code),.vditor-reset table td:has(code){max-width:none!important;}"))
        XCTAssertTrue(css.contains(".vditor-reset table td code,.vditor-reset table th code{white-space:nowrap!important;"))
        XCTAssertFalse(css.contains("word-break:break-word"))
    }
}
