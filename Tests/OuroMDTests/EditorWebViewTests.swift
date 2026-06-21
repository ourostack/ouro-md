import XCTest
@testable import OuroMD

final class EditorWebViewTests: XCTestCase {
    func testInitialThemeBootstrapSeedsDarkThemeBeforeEditorReady() {
        let script = EditorWebView.initialThemeBootstrapScript(for: ThemeStore.shared.theme(id: "graphite"))

        XCTAssertTrue(script.contains("__ouroInitialTheme"))
        XCTAssertTrue(script.contains("github-dark"))
        XCTAssertTrue(script.contains("#2c2c2e"))
        XCTAssertTrue(script.contains("ouro-theme"))
        XCTAssertTrue(script.contains("ouro-initial-background"))
        XCTAssertTrue(script.contains("background-color"))
        XCTAssertTrue(script.contains("important"))
    }
}
