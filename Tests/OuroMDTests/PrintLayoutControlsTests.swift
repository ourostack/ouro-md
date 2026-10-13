import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintLayoutControlsTests: XCTestCase {
    func testCitationAndHeadingChoicesPersistAndInvalidatePreviewSettings() {
        let preferences = InMemoryPrintLayoutPreferenceStore()
        let store = PrintLayoutSettingsStore(preferences: preferences)
        let controller = PrintLayoutAccessoryController(settings: .default, settingsStore: store)
        controller.loadViewIfNeeded()
        var changed: PrintLayoutSettings?
        controller.onSettingsChanged = { changed = $0 }
        controller.setFieldValues(top: "54", right: "54", bottom: "54", left: "54", fontSize: "12", lineSpacing: "1.45", includeExternalLinks: false, citationMode: .pageFootnotes, headingBreakLevel: 2)
        XCTAssertTrue(controller.applyCurrentValues())
        XCTAssertEqual(changed?.effectiveCitationMode, .pageFootnotes)
        XCTAssertEqual(changed?.headingBreakLevel, 2)
        XCTAssertEqual(store.load(), controller.currentSettings)
        controller.setFieldValues(top: "54", right: "54", bottom: "54", left: "54", fontSize: "12", lineSpacing: "1.45", includeExternalLinks: true, citationMode: .endnotes, headingBreakLevel: 0)
        XCTAssertTrue(controller.applyCurrentValues())
        XCTAssertEqual(changed?.effectiveCitationMode, .endnotes)
        XCTAssertEqual(changed?.headingBreakLevel, 0)
        XCTAssertEqual(store.load(), controller.currentSettings)
    }

    func testControlsRejectInvalidNumbersWithoutChangingSettings() {
        let controller = PrintLayoutAccessoryController(
            settings: .default,
            settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore())
        )
        controller.loadViewIfNeeded()
        controller.setFieldValues(
            top: "oops",
            right: "54",
            bottom: "54",
            left: "54",
            fontSize: "12",
            lineSpacing: "1.45",
            includeExternalLinks: false
        )

        XCTAssertFalse(controller.applyCurrentValues())
        XCTAssertEqual(controller.validationMessage, "Top margin must be a finite number.")
        XCTAssertEqual(controller.currentSettings, .default)
    }

    func testControlsRejectOutOfRangeValuesWithoutChangingSettings() {
        let controller = PrintLayoutAccessoryController(
            settings: .default,
            settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore())
        )
        controller.loadViewIfNeeded()
        controller.setFieldValues(
            top: "12",
            right: "54",
            bottom: "54",
            left: "54",
            fontSize: "12",
            lineSpacing: "1.45",
            includeExternalLinks: false
        )

        XCTAssertFalse(controller.applyCurrentValues())
        XCTAssertEqual(controller.validationMessage, "Top margin must be between 18 and 144.")
        XCTAssertEqual(controller.currentSettings, .default)
    }
}
