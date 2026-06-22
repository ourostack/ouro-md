import AppKit
import OuroMDCore
import SwiftUI

/// Headless `--accessibilityaudit`: checks that core native surfaces expose
/// accessible labels/values and that critical menu shortcuts remain present and
/// non-conflicting.
@MainActor
final class AccessibilityAuditTester {
    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-accessibility-audit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "needle in accessible search result\n".write(to: root.appendingPathComponent("result.md"),
                                                          atomically: true,
                                                          encoding: .utf8)

        let model = AppModel()
        model.openFolder(root)
        model.searchQuery = "needle"
        model.runFolderSearch()
        waitUntil(timeout: 5) { !model.searching && !model.searchResults.isEmpty }
        model.showFind()
        model.replaceVisible = true
        model.showCommandPalette()
        model.commandPaletteQuery = "export"
        model.setCounts(words: 123, chars: 456)

        let invalidModel = AppModel()
        invalidModel.openFolder(root)
        invalidModel.setSidebarMode(.search)
        invalidModel.searchQuery = "("
        invalidModel.searchRegexp = true
        invalidModel.runFolderSearch()

        let updateCoordinator = makeInstallingUpdateCoordinator()
        let installingTask = Task {
            await updateCoordinator.checkForReleaseUpdate()
            await updateCoordinator.installReleaseUpdate(destinationBundle: URL(fileURLWithPath: "/tmp/Ouro MD.app"))
        }
        waitUntil(timeout: 3) { updateCoordinator.installStatus?.contains("Downloading") == true }
        waitUntil(timeout: 3) { updateCoordinator.installError != nil }
        installingTask.cancel()

        let labels = accessibilityStrings(
            PreferencesView(model: model, updateCoordinator: OuroMDUpdateCoordinator(), telemetry: OuroMDTelemetry.shared),
            size: NSSize(width: 540, height: 380)
        )
        .union(accessibilityStrings(SidebarView(model: model), size: NSSize(width: 320, height: 720)))
        .union(accessibilityStrings(SidebarView(model: invalidModel), size: NSSize(width: 320, height: 720)))
        .union(accessibilityStrings(EditorPane(model: model), size: NSSize(width: 680, height: 520)))
        .union(accessibilityStrings(CommandReferenceView(items: CommandPaletteCatalog.items()), size: NSSize(width: 560, height: 620)))
        .union(accessibilityStrings(OuroMDAboutView(updateCoordinator: makeCurrentUpdateCoordinator()), size: NSSize(width: 540, height: 540)))
        .union(accessibilityStrings(UpdateProgressView(updateCoordinator: updateCoordinator), size: NSSize(width: 440, height: 190)))

        let runtimeRequired = ["Light", "Dark", "Outline", "Files", "Search"]
        let missingRuntime = runtimeRequired.filter { expected in
            !labels.contains { $0.localizedCaseInsensitiveContains(expected) }
        }
        let source = sourceAccessibilityAudit()
        let menu = menuAudit()
        let discoverability = commandDiscoverabilityAudit()
        let labelsOK = missingRuntime.isEmpty && source.missing.isEmpty && discoverability.missing.isEmpty

        print("runtime accessibility smoke: \(missingRuntime.isEmpty ? "✓" : "✗")")
        if !missingRuntime.isEmpty {
            print("missing runtime labels: \(missingRuntime.joined(separator: " | "))")
            print("observed labels: \(labels.sorted().joined(separator: " | "))")
        }
        print("source accessibility labels: \(source.missing.isEmpty ? "✓" : "✗")")
        if !source.missing.isEmpty {
            print("missing source labels: \(source.missing.joined(separator: " | "))")
        }
        print("menu shortcut coverage: \(menu.coverageOK ? "✓" : "✗")")
        if !menu.missingCritical.isEmpty {
            print("missing shortcuts: \(menu.missingCritical.joined(separator: " | "))")
        }
        print("menu shortcut conflicts: \(menu.conflicts.isEmpty ? "✓" : "✗")")
        if !menu.conflicts.isEmpty {
            print("shortcut conflicts: \(menu.conflicts.joined(separator: " | "))")
        }
        print("command discoverability catalog: \(discoverability.missing.isEmpty ? "✓" : "✗")")
        if !discoverability.missing.isEmpty {
            print("missing discoverable commands: \(discoverability.missing.joined(separator: " | "))")
        }

        model.teardown()
        invalidModel.teardown()
        try? FileManager.default.removeItem(at: root)
        exit(labelsOK && menu.coverageOK && menu.conflicts.isEmpty ? 0 : 1)
    }

    private func accessibilityStrings<Content: View>(_ view: Content, size: NSSize) -> Set<String> {
        let host = NSHostingController(rootView: view)
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
        let strings = collectAccessibilityStrings(from: host.view)
        window.orderOut(nil)
        return strings
    }

    private func collectAccessibilityStrings(from root: Any?) -> Set<String> {
        guard let object = root as AnyObject? else { return [] }
        var out: Set<String> = []
        func add(_ value: String?) {
            guard let value, !value.isEmpty else { return }
            out.insert(value)
        }
        add(object.accessibilityLabel?())
        add(object.accessibilityTitle?())
        add(object.accessibilityHelp?())
        let children = (object.accessibilityChildren?() ?? [])
            + (object.accessibilityVisibleChildren?() ?? [])
        for child in children {
            out.formUnion(collectAccessibilityStrings(from: child))
        }
        if let view = object as? NSView {
            for subview in view.subviews {
                out.formUnion(collectAccessibilityStrings(from: subview))
            }
        }
        return out
    }

    private struct SourceAuditResult {
        var missing: [String]
    }

    private func sourceAccessibilityAudit() -> SourceAuditResult {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sources = ["Sources/OuroMD/ContentView.swift", "Sources/OuroMD/Sidebar.swift", "Sources/OuroMD/CommandReferenceView.swift", "Sources/OuroMD/AppInfoView.swift"]
            .compactMap { try? String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        let requiredSnippets = [
            ".accessibilityLabel(\"Appearance\")",
            ".accessibilityLabel(\"Theme\")",
            "Toggle(\"Save changes automatically\"",
            "Toggle(\"Close brackets and quotes automatically\"",
            "Toggle(\"Check for updates automatically\"",
            ".accessibilityLabel(\"Text size\")",
            ".accessibilityLabel(\"Sidebar section\")",
            ".accessibilityLabel(\"Search text in folder\")",
            "opt(\"Aa\",",
            "opt(\"Word\",",
            "opt(\".*\",",
            ".accessibilityLabel(\"Search folder\")",
            ".accessibilityLabel(\"Command palette\")",
            ".accessibilityLabel(\"Command\")",
            ".accessibilityLabel(\"Close command palette\")",
            ".accessibilityLabel(\"Keyboard shortcuts\")",
            ".accessibilityLabel(\"Search commands\")",
            ".accessibilityLabel(\"About Ouro MD\")",
            ".accessibilityLabel(\"Update status\")",
            ".accessibilityLabel(\"Update state\")",
            ".accessibilityLabel(\"Check for updates\")",
            ".accessibilityLabel(\"Open release\")",
            ".accessibilityLabel(\"Document status\")",
            ".accessibilityLabel(\"Find\")",
            ".accessibilityLabel(\"Replace\")",
            ".accessibilityLabel(\"Previous match\")",
            ".accessibilityLabel(\"Next match\")",
            ".accessibilityLabel(\"Toggle Replace\")",
            ".accessibilityLabel(\"Close Find\")",
            ".accessibilityLabel(progress.title.isEmpty ?",
            ".accessibilityLabel(\"Retry update\")",
        ]
        return SourceAuditResult(missing: requiredSnippets.filter { !sources.contains($0) })
    }

    private struct MenuAuditResult {
        var coverageOK: Bool
        var missingCritical: [String]
        var conflicts: [String]
    }

    private func menuAudit() -> MenuAuditResult {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        let delegate = AppDelegate()
        MenuBuilder.install(into: app, target: delegate)

        let critical: [(path: [String], key: String, modifiers: NSEvent.ModifierFlags)] = [
            (["File", "Open…"], "o", [.command]),
            (["File", "Open Folder…"], "o", [.command, .shift]),
            (["File", "Save"], "s", [.command]),
            (["File", "Save As…"], "s", [.command, .shift]),
            (["Edit", "Command Palette…"], "p", [.command, .shift]),
            (["Help", "Keyboard Shortcuts…"], "/", [.command, .shift]),
            (["Edit", "Find", "Find…"], "f", [.command]),
            (["Edit", "Find", "Replace…"], "f", [.command, .option]),
            (["View", "Toggle Sidebar"], "l", [.command, .shift]),
            (["View", "Outline"], "1", [.command, .control]),
            (["View", "File Tree"], "3", [.command, .control]),
            (["View", "Search"], "f", [.command, .shift]),
            (["Paragraph", "Heading 1"], "1", [.command]),
            (["Format", "Bold"], "b", [.command]),
            (["Format", "Italic"], "i", [.command]),
        ]
        let missing = critical.compactMap { item -> String? in
            guard let menuItem = findMenuItem(path: item.path, in: app.mainMenu) else {
                return item.path.joined(separator: " ▸ ")
            }
            let keyOK = menuItem.keyEquivalent == item.key
            let mask = menuItem.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
            let maskOK = mask == item.modifiers
            return keyOK && maskOK ? nil : "\(item.path.joined(separator: " ▸ ")) expected \(shortcut(item.key, item.modifiers))"
        }
        var signatures: [String: [String]] = [:]
        collectMenuItems(app.mainMenu).forEach { item in
            guard item.isEnabled, !item.keyEquivalent.isEmpty else { return }
            let mask = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
            let signature = shortcut(item.keyEquivalent, mask)
            signatures[signature, default: []].append(item.title)
        }
        let conflicts = signatures
            .filter { $0.value.count > 1 }
            .map { "\($0.key): \($0.value.joined(separator: ", "))" }
            .sorted()
        return MenuAuditResult(coverageOK: missing.isEmpty, missingCritical: missing, conflicts: conflicts)
    }

    private struct CommandDiscoverabilityResult {
        var missing: [String]
    }

    private func commandDiscoverabilityAudit() -> CommandDiscoverabilityResult {
        let items = Dictionary(uniqueKeysWithValues: CommandPaletteCatalog.items().map { ($0.id, $0) })
        let required: [(String, String)] = [
            ("edit.command-palette", "⇧⌘P"),
            ("help.keyboard-shortcuts", "⌘?"),
            ("file.open-folder", "⇧⌘O"),
            ("edit.find", "⌘F"),
            ("edit.replace", "⌥⌘F"),
            ("edit.find-next", "⌘G"),
            ("edit.find-previous", "⇧⌘G"),
            ("edit.paste-plain", "⇧⌘V"),
            ("view.search-sidebar", "⇧⌘F"),
            ("view.outline-sidebar", "⌃⌘1"),
            ("format.bold", "⌘B"),
            ("paragraph.h6", "⌘6"),
            ("paragraph.quote", ""),
            ("paragraph.codeblock", ""),
            ("paragraph.math", ""),
            ("paragraph.hr", ""),
            ("help.about", ""),
            ("help.whats-new", ""),
            ("help.check-updates", ""),
            ("help.open-latest-release", ""),
        ]
        let missing = required.compactMap { id, shortcut -> String? in
            guard let item = items[id] else { return "\(id) missing" }
            if shortcut.isEmpty { return nil }
            return item.shortcut == shortcut ? nil : "\(id) expected \(shortcut)"
        }
        return CommandDiscoverabilityResult(missing: missing)
    }

    private func findMenuItem(path: [String], in menu: NSMenu?) -> NSMenuItem? {
        guard let first = path.first, let menu else { return nil }
        if path.count == 1 {
            return menu.item(withTitle: first)
                ?? menu.items.first { $0.submenu?.title == first }
        }
        guard let item = menu.item(withTitle: first)
                ?? menu.items.first(where: { $0.submenu?.title == first }) else {
            return nil
        }
        return findMenuItem(path: Array(path.dropFirst()), in: item.submenu)
    }

    private func collectMenuItems(_ menu: NSMenu?) -> [NSMenuItem] {
        guard let menu else { return [] }
        var out: [NSMenuItem] = []
        for item in menu.items {
            out.append(item)
            out.append(contentsOf: collectMenuItems(item.submenu))
        }
        return out
    }

    private func shortcut(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> String {
        var prefix = ""
        if modifiers.contains(.control) { prefix += "^" }
        if modifiers.contains(.option) { prefix += "⌥" }
        if modifiers.contains(.shift) { prefix += "⇧" }
        if modifiers.contains(.command) { prefix += "⌘" }
        return prefix + key
    }

    private func makeInstallingUpdateCoordinator() -> OuroMDUpdateCoordinator {
        let defaults = UserDefaults(suiteName: "ouro-accessibility-audit-\(UUID().uuidString)") ?? .standard
        return OuroMDUpdateCoordinator(
            defaults: defaults,
            checker: {
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
            },
            stageUpdate: { _, progress in
                await progress("Downloading Ouro-MD-0.10.0.zip...")
                try await Task.sleep(nanoseconds: 200_000_000)
                throw OuroMDUpdateInstaller.InstallError.download("offline")
            },
            terminate: {},
            telemetry: { _, _ in }
        )
    }

    private func makeCurrentUpdateCoordinator() -> OuroMDUpdateCoordinator {
        let defaults = UserDefaults(suiteName: "ouro-accessibility-current-\(UUID().uuidString)") ?? .standard
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

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
