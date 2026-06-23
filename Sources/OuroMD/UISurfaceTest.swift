import AppKit
import OuroAppShellUI
import OuroMDCore
import SwiftUI
import Vision

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

        let statusModel = AppModel()
        statusModel.setCounts(words: 123, chars: 456)
        statusModel.showCommandPalette()
        statusModel.commandPaletteQuery = "export"
        let editorFitModel = AppModel()
        editorFitModel.showCommandPalette()
        editorFitModel.commandPaletteQuery = "find"

        let updateCoordinator = OuroMDUpdateCoordinator()
        let availableUpdateCoordinator = makeAvailableUpdateCoordinator()
        let installingCoordinator = makeInstallingUpdateCoordinator()
        let prefsSize = fittingSize(
            PreferencesView(model: searchModel, updateCoordinator: updateCoordinator, telemetry: OuroMDTelemetry.shared),
            constrainedTo: NSSize(width: 560, height: 430)
        )
        let aboutSize = fittingSize(
            OuroMDAboutView(updateCoordinator: makeCurrentUpdateCoordinator()),
            constrainedTo: NSSize(width: 520, height: 520)
        )
        let searchSize = fittingSize(
            SidebarView(model: searchModel),
            constrainedTo: NSSize(width: 300, height: 640)
        )
        let editorSize = fittingSize(
            EditorPane(model: editorFitModel),
            constrainedTo: NSSize(width: 520, height: 420)
        )
        let referenceSize = fittingSize(
            CommandReferenceView(items: CommandPaletteCatalog.items()),
            constrainedTo: NSSize(width: 560, height: 620)
        )
        let availableTask = Task {
            await availableUpdateCoordinator.checkForReleaseUpdate()
        }
        waitUntil(timeout: 3) { availableUpdateCoordinator.releaseSnapshot != nil }
        let availableUpdateSize = fittingSize(
            ReleaseUpdateControls(updateCoordinator: availableUpdateCoordinator, showTitle: true)
                .frame(width: 560, alignment: .leading),
            constrainedTo: NSSize(width: 560, height: 220)
        )
        let availableUpdateText = renderedText(
            ReleaseUpdateControls(updateCoordinator: availableUpdateCoordinator, showTitle: true)
                .frame(width: 560, alignment: .leading),
            constrainedTo: NSSize(width: 560, height: 220)
        )
        availableTask.cancel()
        let installingTask = Task {
            await installingCoordinator.checkForReleaseUpdate()
            await installingCoordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))
        }
        waitUntil(timeout: 3) { installingCoordinator.installStatus?.contains("Downloading") == true }
        let installingSize = fittingSize(
            UpdateProgressView(updateCoordinator: installingCoordinator),
            constrainedTo: NSSize(width: 420, height: 160)
        )
        let installingShellState = installingCoordinator.appShellUpdateState
        waitUntil(timeout: 3) { installingCoordinator.installError != nil }
        let failedSize = fittingSize(
            UpdateProgressView(updateCoordinator: installingCoordinator),
            constrainedTo: NSSize(width: 420, height: 180)
        )
        installingTask.cancel()

        let menuOK = menuTopologyIsValid()
        let prefsLabels = accessibilityLabels(
            PreferencesView(model: searchModel, updateCoordinator: updateCoordinator, telemetry: OuroMDTelemetry.shared),
            constrainedTo: NSSize(width: 520, height: 350)
        )
        let sidebarLabels = accessibilityLabels(
            SidebarView(model: searchModel),
            constrainedTo: NSSize(width: 300, height: 640)
        )
        let updateLabels = accessibilityLabels(
            UpdateProgressView(updateCoordinator: installingCoordinator),
            constrainedTo: NSSize(width: 420, height: 180)
        )

        let regexErrorOK = invalidModel.searchError?.contains("Invalid regular expression") == true
        let searchResultsOK = !searchModel.searchResults.isEmpty && searchModel.searchError == nil
        let prefsOK = prefsSize.width <= 580 && prefsSize.height <= 460
        let aboutOK = aboutSize.width <= 540 && aboutSize.height <= 540
        let searchOK = searchSize.width <= 380 && searchSize.height <= 700
        let editorOK = editorSize.width <= 560 && editorSize.height <= 460
        let referenceOK = referenceSize.width <= 600 && referenceSize.height <= 660
        let statusPaletteOK = statusModel.wordCount == 123
            && statusModel.charCount == 456
            && statusModel.commandPaletteVisible
            && containsAll(Set(statusModel.commandPaletteItems.map(\.title)), ["Export HTML", "Export PDF"])
        let commandDiscoveryOK = CommandPaletteCatalog.items().contains { $0.id == "edit.command-palette" && $0.shortcut == "⇧⌘P" }
            && CommandPaletteCatalog.items().contains { $0.id == "help.keyboard-shortcuts" && $0.shortcut == "⌘?" }
            && CommandPaletteCatalog.items().contains { $0.id == "help.about" }
            && CommandPaletteCatalog.items().contains { $0.id == "help.whats-new" }
            && CommandPaletteCatalog.items().contains { $0.id == "help.check-updates" }
            && CommandPaletteCatalog.items().contains { $0.id == "help.open-latest-release" }
            && editorFitModel.commandPaletteItems.contains { $0.id == "edit.find" && $0.shortcut == "⌘F" }
        let installingOK = installingCoordinator.installStatus?.contains("Downloading") == true || installingCoordinator.installError != nil
        let progressOK = installingSize.width <= 420 && installingSize.height <= 160 && failedSize.width <= 420 && failedSize.height <= 180
        let installingReviewStateOK = installingShellState.kind == .installing && installingShellState.canReviewUpdate
        let availableShellState = availableUpdateCoordinator.appShellUpdateState
        let availableShellActions = availableUpdateCoordinator.appShellUpdateActions
        let availableUpdateSizeOK = availableUpdateSize.width <= 560 && availableUpdateSize.height <= 220
        let availableTextOK = containsAll(availableUpdateText, ["Review Update", "Open Release"])
            && !availableUpdateText.contains {
                ($0.localizedCaseInsensitiveContains("Install")
                    && $0.localizedCaseInsensitiveContains("Relaunch"))
            }
        let directInstallSuppressedOK = availableShellState.kind == .updateAvailable
            && availableShellState.canReviewUpdate
            && availableShellState.canOpenReleasePage
            && !availableShellState.canInstallUpdate
            && availableShellActions.reviewUpdate != nil
            && availableShellActions.openReleasePage != nil
            && availableShellActions.installAndRelaunch == nil
            && availableUpdateSizeOK
            && availableTextOK
        let axOK = containsAll(prefsLabels, ["Light", "Dark"])
            && containsAll(sidebarLabels, ["Outline", "Files", "Search"])
            && (containsAll(updateLabels, ["Update failed"]) || updateLabels.isEmpty)

        print(String(format: "preferences fitting size: %.1fx%.1f %@", prefsSize.width, prefsSize.height, prefsOK ? "✓" : "✗"))
        print(String(format: "about fitting size: %.1fx%.1f %@", aboutSize.width, aboutSize.height, aboutOK ? "✓" : "✗"))
        print(String(format: "search sidebar fitting size: %.1fx%.1f %@", searchSize.width, searchSize.height, searchOK ? "✓" : "✗"))
        print(String(format: "editor palette/status fitting size: %.1fx%.1f %@", editorSize.width, editorSize.height, editorOK ? "✓" : "✗"))
        print(String(format: "command reference fitting size: %.1fx%.1f %@", referenceSize.width, referenceSize.height, referenceOK ? "✓" : "✗"))
        print("status/palette semantic state: \(statusPaletteOK ? "✓" : "✗")")
        print("command discoverability semantic state: \(commandDiscoveryOK ? "✓" : "✗")")
        print(String(format: "available update controls fitting size: %.1fx%.1f %@", availableUpdateSize.width, availableUpdateSize.height, availableUpdateSizeOK ? "✓" : "✗"))
        print(String(format: "update progress fitting size: installing %.1fx%.1f failed %.1fx%.1f %@", installingSize.width, installingSize.height, failedSize.width, failedSize.height, progressOK ? "✓" : "✗"))
        print("installing update review state: \(installingReviewStateOK ? "✓" : "✗")")
        print("direct shell install suppressed; review prompt available: \(directInstallSuppressedOK ? "✓" : "✗")")
        print("invalid regex visible state: \(regexErrorOK ? "✓" : "✗")")
        print("search result row state: \(searchResultsOK ? "✓" : "✗")")
        print("menu topology: \(menuOK ? "✓" : "✗")")
        print("accessibility labels: \(axOK ? "✓" : "✗")")
        if !installingReviewStateOK {
            print("installing shell state: \(installingShellState.kind.rawValue), canReviewUpdate=\(installingShellState.canReviewUpdate)")
        }
        if !directInstallSuppressedOK {
            print("available shell state: \(availableShellState.kind.rawValue), canReviewUpdate=\(availableShellState.canReviewUpdate), canOpenReleasePage=\(availableShellState.canOpenReleasePage), canInstallUpdate=\(availableShellState.canInstallUpdate), hasReviewAction=\(availableShellActions.reviewUpdate != nil), hasOpenReleaseAction=\(availableShellActions.openReleasePage != nil), hasInstallAction=\(availableShellActions.installAndRelaunch != nil), renderedTextObservable=\(!availableUpdateText.isEmpty)")
            print("available update text: \(availableUpdateText.sorted().joined(separator: " | "))")
        }
        if !axOK {
            print("preferences labels: \(prefsLabels.sorted().joined(separator: " | "))")
            print("sidebar labels: \(sidebarLabels.sorted().joined(separator: " | "))")
            print("update labels: \(updateLabels.sorted().joined(separator: " | "))")
        }

        invalidModel.teardown()
        searchModel.teardown()
        try? FileManager.default.removeItem(at: root)
        exit(regexErrorOK && searchResultsOK && prefsOK && aboutOK && searchOK && editorOK && referenceOK && statusPaletteOK && commandDiscoveryOK && installingOK && availableUpdateSizeOK && progressOK && installingReviewStateOK && directInstallSuppressedOK && menuOK && axOK ? 0 : 1)
    }

    private func fittingSize<Content: View>(_ view: Content, constrainedTo size: NSSize) -> NSSize {
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        return host.view.fittingSize
    }

    private func accessibilityLabels<Content: View>(_ view: Content, constrainedTo size: NSSize) -> Set<String> {
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.contentView = host.view
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        host.view.layoutSubtreeIfNeeded()
        var labels = collectAccessibilityLabels(from: window)
        labels.formUnion(collectAccessibilityLabels(from: host.view))
        window.orderOut(nil)
        return labels
    }

    private func renderedText<Content: View>(_ view: Content, constrainedTo size: NSSize) -> Set<String> {
        let host = NSHostingController(
            rootView: view
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        host.view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        window.contentView = host.view
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
        host.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        host.view.displayIfNeeded()
        guard let image = snapshot(host.view) else {
            window.orderOut(nil)
            return []
        }
        saveDebugSnapshot(image, name: "available-update-controls")
        window.orderOut(nil)
        return recognizeText(in: image)
    }

    private func snapshot(_ view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private func saveDebugSnapshot(_ image: CGImage, name: String) {
        guard ProcessInfo.processInfo.environment["OURO_MD_UI_SURFACE_DEBUG_SNAPSHOT"] != nil else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-md-\(name).png")
        try? data.write(to: url)
        print("debug snapshot: \(url.path)")
    }

    private func recognizeText(in image: CGImage) -> Set<String> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return Set((request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        })
    }

    private func collectAccessibilityLabels(from root: Any?) -> Set<String> {
        guard let object = root as AnyObject? else { return [] }
        var labels: Set<String> = []
        if let label = object.accessibilityLabel?(), !label.isEmpty {
            labels.insert(label)
        }
        if let title = object.accessibilityTitle?(), !title.isEmpty {
            labels.insert(title)
        }
        if let help = object.accessibilityHelp?(), !help.isEmpty {
            labels.insert(help)
        }
        if let button = object as? NSButton {
            if !button.title.isEmpty {
                labels.insert(button.title)
            }
            let attributedTitle = button.attributedTitle.string
            if !attributedTitle.isEmpty {
                labels.insert(attributedTitle)
            }
        }
        if let textField = object as? NSTextField, !textField.stringValue.isEmpty {
            labels.insert(textField.stringValue)
        }
        let children = (object.accessibilityChildren?() ?? [])
            + (object.accessibilityVisibleChildren?() ?? [])
            + accessibilityChildren(named: "accessibilityChildrenInNavigationOrder", from: object)
        for child in children {
            labels.formUnion(collectAccessibilityLabels(from: child))
        }
        if let view = object as? NSView {
            for subview in view.subviews {
                labels.formUnion(collectAccessibilityLabels(from: subview))
            }
        }
        return labels
    }

    private func accessibilityChildren(named selectorName: String, from object: AnyObject) -> [Any] {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let unmanaged = object.perform(selector) else {
            return []
        }
        let value = unmanaged.takeUnretainedValue()
        if let array = value as? [Any] {
            return array
        }
        if let array = value as? NSArray {
            return array.map { $0 }
        }
        return []
    }

    private func containsAll(_ labels: Set<String>, _ required: [String]) -> Bool {
        required.allSatisfy { expected in
            labels.contains { label in label.localizedCaseInsensitiveContains(expected) }
        }
    }

    private func menuTopologyIsValid() -> Bool {
        let app = NSApplication.shared
        let previousMenu = app.mainMenu
        defer { app.mainMenu = previousMenu }
        let delegate = AppDelegate()
        MenuBuilder.install(into: app, target: delegate)
        let titles = app.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        let expected = ["File", "Edit", "Paragraph", "Format", "View", "Themes", "Window", "Help"]
        guard expected.allSatisfy({ titles.contains($0) }) else { return false }
        guard let file = app.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == "File" }),
              let edit = app.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == "Edit" }),
              let view = app.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == "View" }) else {
            return false
        }
        let help = app.mainMenu?.items.compactMap(\.submenu).first(where: { $0.title == "Help" })
        return file.item(withTitle: "Open…")?.keyEquivalent == "o"
            && file.item(withTitle: "Open Recent")?.submenu?.title == "Open Recent"
            && edit.item(withTitle: "Command Palette…")?.keyEquivalent == "p"
            && edit.item(withTitle: "Find")?.submenu?.item(withTitle: "Find…")?.keyEquivalent == "f"
            && view.item(withTitle: "Search")?.action == #selector(AppDelegate.showSearchSidebar(_:))
            && help?.item(withTitle: "What's New")?.action == #selector(AppDelegate.showWhatsNew(_:))
            && help?.item(withTitle: "Check for Updates…")?.action == #selector(AppDelegate.checkForUpdates(_:))
            && help?.item(withTitle: "Open Latest Release")?.action == #selector(AppDelegate.openLatestReleasePage(_:))
    }

    private func makeCurrentUpdateCoordinator() -> OuroMDUpdateCoordinator {
        let defaults = UserDefaults(suiteName: "ouro-ui-current-\(UUID().uuidString)") ?? .standard
        return OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: {
                ReleaseUpdateSnapshot(
                    status: .current,
                    currentVersion: OuroMDRelease.version,
                    latestVersion: OuroMDRelease.version,
                    tagName: "v\(OuroMDRelease.version)",
                    htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v\(OuroMDRelease.version)",
                    publishedAt: "2026-06-22T19:00:06Z",
                    body: "Release notes for visible update state.",
                    assets: [],
                    detail: "Version \(OuroMDRelease.version) is current."
                )
            },
            terminate: {},
            telemetry: { _, _ in }
        )
    }

    private func makeInstallingUpdateCoordinator() -> OuroMDUpdateCoordinator {
        let defaults = UserDefaults(suiteName: "ouro-ui-surface-\(UUID().uuidString)") ?? .standard
        return OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: {
                self.availableUpdateSnapshot()
            },
            stageUpdate: { _, progress in
                await progress("Downloading Ouro-MD-0.10.0.zip...")
                try await Task.sleep(nanoseconds: 300_000_000)
                throw OuroMDUpdateInstaller.InstallError.download("offline")
            },
            terminate: {},
            telemetry: { _, _ in }
        )
    }

    private func makeAvailableUpdateCoordinator() -> OuroMDUpdateCoordinator {
        let defaults = UserDefaults(suiteName: "ouro-ui-available-\(UUID().uuidString)") ?? .standard
        return OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: {
                self.availableUpdateSnapshot()
            },
            terminate: {},
            telemetry: { _, _ in }
        )
    }

    private func availableUpdateSnapshot() -> ReleaseUpdateSnapshot {
        ReleaseUpdateSnapshot(
            status: .updateAvailable,
            currentVersion: "0.9.0",
            latestVersion: "0.10.0",
            tagName: "v0.10.0",
            htmlURL: "https://github.com/ourostack/ouro-md/releases/tag/v0.10.0",
            assets: [
                ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.zip", downloadURL: "https://example.test/Ouro-MD-0.10.0.zip", size: 100),
                ReleaseUpdateAsset(name: "Ouro-MD-0.10.0.manifest.json", downloadURL: "https://example.test/Ouro-MD-0.10.0.manifest.json", size: 50),
            ],
            detail: "Version 0.10.0 is available."
        )
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
