import AppKit
import UniformTypeIdentifiers

/// Imperative bridge to the live web editor, implemented by the web view's coordinator.
protocol EditorBridge: AnyObject {
    func setMarkdown(_ markdown: String)
    func getMarkdown(_ completion: @escaping (String) -> Void)
    func getHTML(_ completion: @escaping (String) -> Void)
    func applyTheme(uiMode: String, css: String)
    func setMode(_ mode: String)
    func setOutline(_ on: Bool)
    func execCommand(_ command: String)
    func markSaved()
    func focusEditor()
    func setZoom(_ factor: Double)
}

/// Owns document state (current file, dirty flag, theme/mode) and orchestrates
/// file, theme, and export operations against the web editor.
final class AppModel {
    private(set) var currentURL: URL?
    private(set) var isDirty = false
    private(set) var isReady = false
    private(set) var themeID: String
    private(set) var mode = "ir"
    private(set) var showOutline = false
    private var zoom = 1.0

    weak var bridge: EditorBridge?
    /// Invoked whenever window-chrome-relevant state changes.
    var onChromeUpdate: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var pendingMarkdown: String?

    init() {
        themeID = UserDefaults.standard.string(forKey: "ouro.theme") ?? "quartz"
    }

    var theme: Theme { ThemeStore.shared.theme(id: themeID) }
    var windowTitle: String { currentURL?.lastPathComponent ?? "Untitled" }

    static let mdTypes: [UTType] = {
        var types: [UTType] = []
        for ext in ["md", "markdown", "mdown", "mkd", "mdtext"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        types.append(contentsOf: [.plainText, .text])
        return types
    }()

    // MARK: - Editor lifecycle

    func editorDidBecomeReady() {
        isReady = true
        applyThemeToEditor()
        if let pending = pendingMarkdown {
            bridge?.setMarkdown(pending)
            pendingMarkdown = nil
        }
        bridge?.setMode(mode)
        bridge?.setOutline(showOutline)
        bridge?.setZoom(zoom)
        onChromeUpdate?()
    }

    func setDirty(_ dirty: Bool) {
        guard dirty != isDirty else { return }
        isDirty = dirty
        onChromeUpdate?()
    }

    // MARK: - File operations

    func newDocument() {
        confirmDiscard { [weak self] in
            guard let self else { return }
            self.currentURL = nil
            self.pushMarkdown("")
            self.isDirty = false
            self.onChromeUpdate?()
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AppModel.mdTypes
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url { open(url: url) }
    }

    func open(url: URL) {
        confirmDiscard { [weak self] in
            guard let self else { return }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                self.currentURL = url
                self.pushMarkdown(text)
                self.isDirty = false
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self.onChromeUpdate?()
            } catch {
                self.presentError("Could not open \(url.lastPathComponent)", error)
            }
        }
    }

    func loadInitialFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        currentURL = url
        pushMarkdown(text)
        isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        onChromeUpdate?()
    }

    func save() { performSave { _ in } }

    func saveAs() {
        runSavePanel(defaultName: currentURL?.lastPathComponent ?? "Untitled.md") { [weak self] url in
            guard let self, let url else { return }
            self.currentURL = url
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            self.writeMarkdown(to: url) { _ in }
        }
    }

    /// Saves the current document, prompting for a location if it is untitled.
    func performSave(completion: @escaping (Bool) -> Void) {
        if let url = currentURL {
            writeMarkdown(to: url, completion: completion)
        } else {
            runSavePanel(defaultName: "Untitled.md") { [weak self] url in
                guard let self, let url else { completion(false); return }
                self.currentURL = url
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self.writeMarkdown(to: url, completion: completion)
            }
        }
    }

    private func writeMarkdown(to url: URL, completion: @escaping (Bool) -> Void) {
        guard let bridge else { completion(false); return }
        bridge.getMarkdown { [weak self] markdown in
            guard let self else { completion(false); return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                self.bridge?.markSaved()
                self.isDirty = false
                self.onChromeUpdate?()
                completion(true)
            } catch {
                self.presentError("Could not save \(url.lastPathComponent)", error)
                completion(false)
            }
        }
    }

    // MARK: - Export

    func exportHTML() {
        runSavePanel(defaultName: exportBaseName() + ".html", types: [.html]) { [weak self] url in
            guard let self, let url else { return }
            self.bridge?.getHTML { body in
                let doc = HTMLDocument.wrap(body: body, css: self.theme.css, title: url.lastPathComponent)
                do { try doc.write(to: url, atomically: true, encoding: .utf8) }
                catch { self.presentError("Could not export HTML", error) }
            }
        }
    }

    func exportPDF() {
        runSavePanel(defaultName: exportBaseName() + ".pdf", types: [.pdf]) { [weak self] url in
            guard let self, let url else { return }
            self.bridge?.getHTML { body in
                let doc = HTMLDocument.wrap(body: body, css: self.theme.css, title: url.lastPathComponent)
                PDFExporter().export(html: doc, to: url) { ok in
                    if !ok {
                        self.presentError("Could not export PDF",
                                          NSError(domain: "ouro-md", code: 1,
                                                  userInfo: [NSLocalizedDescriptionKey: "PDF rendering failed."]))
                    }
                }
            }
        }
    }

    private func exportBaseName() -> String {
        currentURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    // MARK: - View / theme / format

    func setTheme(id: String) {
        themeID = id
        defaults.set(id, forKey: "ouro.theme")
        applyThemeToEditor()
    }

    private func applyThemeToEditor() {
        bridge?.applyTheme(uiMode: theme.uiMode, css: theme.editorCSS)
    }

    func setMode(_ newMode: String) {
        mode = newMode
        bridge?.setMode(newMode)
    }

    func toggleOutline() {
        showOutline.toggle()
        bridge?.setOutline(showOutline)
    }

    func zoomIn() { zoom = min(zoom + 0.1, 3.0); bridge?.setZoom(zoom) }
    func zoomOut() { zoom = max(zoom - 0.1, 0.5); bridge?.setZoom(zoom) }
    func actualSize() { zoom = 1.0; bridge?.setZoom(zoom) }
    func format(_ command: String) { bridge?.execCommand(command) }

    // MARK: - Helpers

    private func pushMarkdown(_ markdown: String) {
        if isReady {
            bridge?.setMarkdown(markdown)
        } else {
            pendingMarkdown = markdown
        }
    }

    func confirmDiscard(then proceed: @escaping () -> Void) {
        guard isDirty else { proceed(); return }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to \(windowTitle)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: performSave { ok in if ok { proceed() } }
        case .alertSecondButtonReturn: proceed()
        default: break
        }
    }

    private func runSavePanel(defaultName: String, types: [UTType] = AppModel.mdTypes,
                              completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        completion(panel.runModal() == .OK ? panel.url : nil)
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
