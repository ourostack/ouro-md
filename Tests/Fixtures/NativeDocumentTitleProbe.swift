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
                guard let window = document.windowForSheet, let screen = window.screen else { exit(1) }
                let frame = window.frame
                let region = "\(Int(frame.minX)),\(Int(screen.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
                let documentClass = String(describing: type(of: document))
                // A native renaming session can track events synchronously.
                // Capture its owned region independently of that modal loop.
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    do {
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        process.arguments = ["-x", "-R", region,
                                             output.appendingPathComponent("native-title-region.png").path]
                        try process.run()
                        process.waitUntilExit()
                        guard process.terminationStatus == 0 else { exit(1) }
                        try JSONSerialization.data(withJSONObject: [
                            "registeredDocumentClass": documentClass,
                            "ownedWindowRegion": region, "captureIndependentOfRenameReturn": true
                        ], options: [.prettyPrinted, .sortedKeys])
                            .write(to: output.appendingPathComponent("packaged-title-probe.json"))
                        exit(0)
                    } catch {
                        fputs("Native title capture failed: \(error)\n", stderr)
                        exit(1)
                    }
                }
                document.rename(rename)
            }
        }
        app.run()
    }
}
