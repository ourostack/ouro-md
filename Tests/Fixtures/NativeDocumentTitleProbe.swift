import AppKit

@MainActor
@objc(NativeDocumentTitleProbeDocument)
final class NativeDocumentTitleProbeDocument: NSDocument {
    private var contents = Data()
    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override func read(from data: Data, ofType typeName: String) throws {
        MainActor.assumeIsolated { contents = data }
    }
    override func data(ofType typeName: String) throws -> Data { contents }
    override func makeWindowControllers() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 720, height: 520),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = NSTextField(labelWithString: "Public fictional document title controls probe")
        addWindowController(NSWindowController(window: window))
    }
}

@MainActor
@main
enum NativeDocumentTitleProbe {
    static func main() {
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
              CommandLine.arguments.count == 3 else { exit(64) }
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let rename = NSMenuItem(title: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        fileMenu.addItem(rename)
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        app.mainMenu = menu
        app.finishLaunching()
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { document, _, error in
            guard let document, error == nil else {
                fputs("Native document open failed: \(String(describing: error))\n", stderr)
                exit(1)
            }
            app.activate(ignoringOtherApps: true)
            document.windowForSheet?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                document.rename(rename)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    do {
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        let windows = app.windows.filter(\.isVisible)
                        var records: [[String: Any]] = []
                        for (index, window) in windows.enumerated() {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                            process.arguments = ["-x", "-o", "-l", "\(window.windowNumber)",
                                                 output.appendingPathComponent("native-window-\(index).png").path]
                            try process.run()
                            process.waitUntilExit()
                            guard process.terminationStatus == 0 else { exit(1) }
                            records.append(["title": window.title, "frame": NSStringFromRect(window.frame)])
                        }
                        try JSONSerialization.data(withJSONObject: [
                            "registeredDocumentClass": String(describing: type(of: document)),
                            "windows": records, "applicationActive": app.isActive
                        ], options: [.prettyPrinted, .sortedKeys])
                            .write(to: output.appendingPathComponent("packaged-title-probe.json"))
                        exit(0)
                    } catch {
                        fputs("Native title capture failed: \(error)\n", stderr)
                        exit(1)
                    }
                }
            }
        }
        app.run()
    }
}
