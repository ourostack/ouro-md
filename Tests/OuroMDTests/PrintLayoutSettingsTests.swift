import XCTest
@testable import OuroMD

final class PrintLayoutSettingsTests: XCTestCase {
    func testDefaultsProvideReadablePrintLayout() {
        let store = InMemoryPrintLayoutPreferenceStore()

        let settings = PrintLayoutSettingsStore(preferences: store).load()

        XCTAssertEqual(settings.margins.top, 54)
        XCTAssertEqual(settings.margins.right, 54)
        XCTAssertEqual(settings.margins.bottom, 54)
        XCTAssertEqual(settings.margins.left, 54)
        XCTAssertEqual(settings.fontSize, 12)
        XCTAssertEqual(settings.lineSpacing, 1.45)
        XCTAssertTrue(settings.includeExternalLinkReferences)
    }

    func testStoreRoundsTripAndClampsInvalidValues() {
        let store = InMemoryPrintLayoutPreferenceStore()
        let settingsStore = PrintLayoutSettingsStore(preferences: store)
        let saved = PrintLayoutSettings(
            margins: PrintPageMargins(top: -12, right: 720, bottom: 0, left: 36),
            fontSize: 4,
            lineSpacing: 9,
            includeExternalLinkReferences: false
        )

        settingsStore.save(saved)
        let reloaded = settingsStore.load()

        XCTAssertEqual(reloaded.margins.top, 18)
        XCTAssertEqual(reloaded.margins.right, 144)
        XCTAssertEqual(reloaded.margins.bottom, 18)
        XCTAssertEqual(reloaded.margins.left, 36)
        XCTAssertEqual(reloaded.fontSize, 8)
        XCTAssertEqual(reloaded.lineSpacing, 3)
        XCTAssertFalse(reloaded.includeExternalLinkReferences)
    }
}
