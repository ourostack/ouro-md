import XCTest
@testable import OuroMD

final class PrintLayoutSettingsTests: XCTestCase {
    func testExplicitLegacyReferencesOnMigratesToEndnotes() {
        let preferences = InMemoryPrintLayoutPreferenceStore()
        preferences.set(true, forKey: "ouro.printLayout.includeExternalLinks")

        let settings = PrintLayoutSettingsStore(preferences: preferences).load()

        XCTAssertEqual(settings.effectiveCitationMode, .endnotes)
    }

    func testExplicitLegacyReferencesOffMigratesToOriginalLinks() {
        let preferences = InMemoryPrintLayoutPreferenceStore()
        preferences.set(false, forKey: "ouro.printLayout.includeExternalLinks")

        let settings = PrintLayoutSettingsStore(preferences: preferences).load()

        XCTAssertEqual(settings.effectiveCitationMode, .originalLinks)
    }

    func testNewUsersWithoutCitationPreferencesDefaultToPageFootnotes() {
        let preferences = InMemoryPrintLayoutPreferenceStore()

        let settings = PrintLayoutSettingsStore(preferences: preferences).load()

        XCTAssertEqual(settings.effectiveCitationMode, .pageFootnotes)
    }

    func testNewCitationPreferenceTakesPriorityOverEitherLegacyFlag() {
        for legacy in [true, false] {
            for mode in [PrintLayoutSettings.CitationMode.originalLinks, .endnotes, .pageFootnotes] {
                let preferences = InMemoryPrintLayoutPreferenceStore()
                preferences.set(legacy, forKey: "ouro.printLayout.includeExternalLinks")
                preferences.set(Double(mode.rawValue), forKey: "ouro.printLayout.citationMode")

                let settings = PrintLayoutSettingsStore(preferences: preferences).load()

                XCTAssertEqual(settings.effectiveCitationMode, mode, "The new citation choice must override legacy \(legacy)")
            }
        }
    }

    func testPrinterImageableAreaRejectsMarginsThatWouldClipOutput() throws {
        let settings = PrintLayoutSettings.default
        XCTAssertNoThrow(try settings.validatePrintableArea(paperSize: NSSize(width: 612, height: 792), imageableBounds: CGRect(x: 18, y: 18, width: 576, height: 756)))
        XCTAssertThrowsError(try settings.validatePrintableArea(paperSize: NSSize(width: 612, height: 792), imageableBounds: CGRect(x: 72, y: 72, width: 468, height: 648)))
    }

    func testDefaultsProvideReadablePrintLayout() {
        let store = InMemoryPrintLayoutPreferenceStore()

        let settings = PrintLayoutSettingsStore(preferences: store).load()

        XCTAssertEqual(settings.margins.top, 54)
        XCTAssertEqual(settings.margins.right, 54)
        XCTAssertEqual(settings.margins.bottom, 54)
        XCTAssertEqual(settings.margins.left, 54)
        XCTAssertEqual(settings.fontSize, 12)
        XCTAssertEqual(settings.lineSpacing, 1.45)
        XCTAssertFalse(settings.includeExternalLinkReferences)
    }

    func testStoreRoundsTripAndClampsInvalidValues() {
        let store = InMemoryPrintLayoutPreferenceStore()
        let settingsStore = PrintLayoutSettingsStore(preferences: store)
        let saved = PrintLayoutSettings(
            margins: PrintPageMargins(top: -12, right: 720, bottom: 0, left: 36),
            fontSize: 4,
            lineSpacing: 9,
            includeExternalLinkReferences: true
        )

        settingsStore.save(saved)
        let reloaded = settingsStore.load()

        XCTAssertEqual(reloaded.margins.top, 18)
        XCTAssertEqual(reloaded.margins.right, 144)
        XCTAssertEqual(reloaded.margins.bottom, 18)
        XCTAssertEqual(reloaded.margins.left, 36)
        XCTAssertEqual(reloaded.fontSize, 8)
        XCTAssertEqual(reloaded.lineSpacing, 3)
        XCTAssertTrue(reloaded.includeExternalLinkReferences)
    }

    func testNormalizationFallsBackForNonFiniteValues() {
        let settings = PrintLayoutSettings(
            margins: PrintPageMargins(top: .infinity, right: 72, bottom: .nan, left: 36),
            fontSize: .nan,
            lineSpacing: .infinity,
            includeExternalLinkReferences: false
        ).normalized

        XCTAssertEqual(settings.margins.top, 54)
        XCTAssertEqual(settings.margins.bottom, 54)
        XCTAssertEqual(settings.fontSize, 12)
        XCTAssertEqual(settings.lineSpacing, 1.45)
    }

    func testValidateRejectsMarginsWithoutPrintableArea() {
        let settings = PrintLayoutSettings(
            margins: PrintPageMargins(top: 200, right: 200, bottom: 200, left: 200),
            fontSize: 12,
            lineSpacing: 1.45,
            includeExternalLinkReferences: false
        )

        XCTAssertThrowsError(try settings.validate(for: NSSize(width: 250, height: 250))) { error in
            XCTAssertEqual(error as? PrintLayoutSettings.LayoutError, .noPrintableArea)
        }
    }
}
