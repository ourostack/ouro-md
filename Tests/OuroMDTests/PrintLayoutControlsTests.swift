import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintLayoutControlsTests: XCTestCase {
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
