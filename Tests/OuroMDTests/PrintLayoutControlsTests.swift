import AppKit
import XCTest
@testable import OuroMD

@MainActor
final class PrintLayoutControlsTests: XCTestCase {
    func testControlsStayCompactWhenTheirContainerIsTall() async throws {
        let host = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 360, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.alphaValue = 0
        defer { host.close() }
        let scratch = try PrintLayoutTestPaths.makeScratchDirectory(label: "control-geometry")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let session = PrintLayoutSession(settings: .default, printInfo: NSPrintInfo(), documentLoader: { _, _, _ in throw PrintLayoutSession.SessionError.missingPreview }, parentWindow: host, action: .export(scratch.appendingPathComponent("unused.pdf"), { _ in }), settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()), reportError: { _, _ in }, telemetry: { _, _ in }, presentation: .headless)
        session.begin()
        defer { session.panelForTesting.close() }
        let root = try XCTUnwrap(session.panelForTesting.contentView)
        try await Task.sleep(nanoseconds: 30_000_000)
        root.layoutSubtreeIfNeeded()
        let fields = descendants(of: root).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
        XCTAssertEqual(fields.count, 6)
        let centers = fields.map { $0.convert($0.bounds, to: root).midY }.sorted(by: >)
        let gaps = zip(centers, centers.dropFirst()).map { $0 - $1 }
        XCTAssertTrue(gaps.allSatisfy { (20...40).contains($0) }, "Numeric controls must remain a compact group, not absorb spare pane height: \(gaps)")
        XCTAssertLessThanOrEqual(try XCTUnwrap(gaps.max()) - XCTUnwrap(gaps.min()), 2)
        XCTAssertFalse(host.isVisible)
        XCTAssertFalse(host.canBecomeKey)
    }

    func testCitationAndHeadingTitlesFitWithoutTruncation() throws {
        let controller = PrintLayoutAccessoryController(settings: .default, settingsStore: PrintLayoutSettingsStore(preferences: InMemoryPrintLayoutPreferenceStore()))
        controller.loadViewIfNeeded()
        let host = NonActivatingHeadlessHostWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 360, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.alphaValue = 0
        host.contentView = controller.view
        defer { host.close() }
        controller.view.layoutSubtreeIfNeeded()
        let choices = descendants(of: controller.view).compactMap { $0 as? NSPopUpButton }
        XCTAssertEqual(choices.count, 2)
        for choice in choices {
            let font = choice.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let longestTitle = choice.itemTitles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            XCTAssertGreaterThanOrEqual(choice.bounds.width, longestTitle + 24, "Every available choice must fit with its popup indicator: \(choice.itemTitles)")
        }
        XCTAssertFalse(host.isVisible)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

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
