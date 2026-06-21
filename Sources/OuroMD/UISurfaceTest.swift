import AppKit
import SwiftUI

/// Headless `--uisurfacetest`: checks native SwiftUI surfaces that WebKit
/// document probes cannot see, especially the search sidebar and Preferences.
@MainActor
final class UISurfaceTester {
    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-ui-surface-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "needle in a very long line that should truncate inside the search sidebar instead of widening it\n"
            .write(to: root.appendingPathComponent("a-file-with-a-very-long-name-that-must-not-widen-the-sidebar.md"), atomically: true, encoding: .utf8)

        let invalidModel = AppModel()
        invalidModel.openFolder(root)
        invalidModel.setSidebarMode(.search)
        invalidModel.searchQuery = "("
        invalidModel.searchRegexp = true
        invalidModel.runFolderSearch()

        let searchModel = AppModel()
        searchModel.openFolder(root)
        searchModel.setSidebarMode(.search)
        searchModel.searchQuery = "needle"
        searchModel.runFolderSearch()
        waitUntil(timeout: 5) { !searchModel.searching && !searchModel.searchResults.isEmpty }

        let updateCoordinator = OuroMDUpdateCoordinator()
        let prefsSize = fittingSize(
            PreferencesView(model: searchModel, updateCoordinator: updateCoordinator, telemetry: OuroMDTelemetry.shared),
            constrainedTo: NSSize(width: 520, height: 350)
        )
        let searchSize = fittingSize(
            SidebarView(model: searchModel),
            constrainedTo: NSSize(width: 300, height: 640)
        )

        let regexErrorOK = invalidModel.searchError?.contains("Invalid regular expression") == true
        let searchResultsOK = !searchModel.searchResults.isEmpty && searchModel.searchError == nil
        let prefsOK = prefsSize.width <= 520 && prefsSize.height <= 350
        let searchOK = searchSize.width <= 380 && searchSize.height <= 700

        print(String(format: "preferences fitting size: %.1fx%.1f %@", prefsSize.width, prefsSize.height, prefsOK ? "✓" : "✗"))
        print(String(format: "search sidebar fitting size: %.1fx%.1f %@", searchSize.width, searchSize.height, searchOK ? "✓" : "✗"))
        print("invalid regex visible state: \(regexErrorOK ? "✓" : "✗")")
        print("search result row state: \(searchResultsOK ? "✓" : "✗")")

        invalidModel.teardown()
        searchModel.teardown()
        try? FileManager.default.removeItem(at: root)
        exit(regexErrorOK && searchResultsOK && prefsOK && searchOK ? 0 : 1)
    }

    private func fittingSize<Content: View>(_ view: Content, constrainedTo size: NSSize) -> NSSize {
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        return host.view.fittingSize
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
