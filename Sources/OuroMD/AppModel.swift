import AppKit
import Combine
import UniformTypeIdentifiers

/// Imperative bridge to the live web editor, implemented by the web view's coordinator.
protocol EditorBridge: AnyObject {
    func setMarkdown(_ markdown: String)
    /// Replace content while preserving the reader's scroll position (external reload).
    func reloadMarkdown(_ markdown: String)
    func getMarkdown(_ completion: @escaping (String) -> Void)
    func getHTML(_ completion: @escaping (String) -> Void)
    func applyTheme(uiMode: String, css: String, codeTheme: String)
    func setMode(_ mode: String)
    func setOutline(_ on: Bool)
    func setFocusMode(_ on: Bool)
    func setTypewriter(_ on: Bool)
    func scrollToHeading(_ index: Int)
    func find(_ query: String, backward: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool)
    func replace(_ query: String, with replacement: String, all: Bool, caseSensitive: Bool, wholeWord: Bool, regexp: Bool, completion: @escaping (Int) -> Void)
    func clearFind()
    func execCommand(_ command: String)
    func insertText(_ text: String)
    func setDocBase(_ directory: String?)
    func markSaved()
    func focusEditor()
    func printDocument()
    func setZoom(_ factor: Double)
}

/// Owns document state (current file, dirty flag, theme/mode) and orchestrates
/// file, theme, and export operations against the web editor.
final class AppModel: ObservableObject {
    private(set) var currentURL: URL?
    private(set) var isDirty = false
    private(set) var isReady = false
    private(set) var themeID: String
    private(set) var mode = "ir"
    private(set) var showOutline = false
    private(set) var focusMode = false
    private(set) var typewriter = false
    @Published private(set) var zoom = 1.0
    @Published var autoSaveEnabled = true
    @Published private(set) var wordCount = 0
    @Published private(set) var charCount = 0
    @Published var sidebarVisible: Bool
    @Published var sidebarMode: SidebarMode = .outline
    @Published private(set) var outlineItems: [OutlineItem] = []
    @Published private(set) var activeHeadingIndex = -1
    @Published var outlineFilter = ""
    @Published private(set) var folderItems: [FolderItem] = []
    // Mounted-folder browser (Open Folder).
    @Published private(set) var mountedFolder: URL?
    @Published private(set) var folderTree: [FolderNode] = []
    @Published private(set) var folderFlat: [FolderNode] = []
    @Published var folderSort: FolderSort = .natural
    @Published var useTreeView = false
    @Published var folderFilter = ""
    @Published var findVisible = false
    @Published var findQuery = ""
    @Published var replaceVisible = false
    @Published var replaceText = ""
    @Published var findCaseSensitive = false
    @Published var findWholeWord = false
    @Published var findRegexp = false
    @Published var findStatus = ""
    // Folder content search (Search tab).
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searching = false
    @Published var searchCaseSensitive = false
    @Published var searchWholeWord = false
    @Published var searchRegexp = false

    weak var bridge: EditorBridge?
    /// Invoked whenever window-chrome-relevant state changes.
    var onChromeUpdate: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var pendingMarkdown: String?
    private var autosaveItem: DispatchWorkItem?
    /// The content currently on disk (last loaded or saved). Lets the file
    /// watcher distinguish a genuine external edit from our own save echo.
    private var lastLoadedContent: String?
    private var fileWatcher: FileWatcher?
    private var folderWatcher: FolderWatcher?
    private let folderScanQueue = DispatchQueue(label: "md.ouro.folderscan", qos: .userInitiated)
    private let contentSearcher = ContentSearcher()

    init() {
        themeID = UserDefaults.standard.string(forKey: "ouro.theme") ?? "quartz"
        sidebarVisible = UserDefaults.standard.bool(forKey: "ouro.sidebar")
        autoSaveEnabled = UserDefaults.standard.object(forKey: "ouro.autosave") as? Bool ?? true
        zoom = UserDefaults.standard.object(forKey: "ouro.zoom") as? Double ?? 1.0
        if let raw = UserDefaults.standard.string(forKey: "ouro.sidebarMode"), let mode = SidebarMode(rawValue: raw) {
            sidebarMode = mode
        }
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
            bridge?.setDocBase(currentURL?.deletingLastPathComponent().path)
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
        if dirty { scheduleAutosave() }
    }

    func setCounts(words: Int, chars: Int) {
        wordCount = words
        charCount = chars
    }

    /// Typora-style auto-save: silently persists a titled document a moment
    /// after the last edit, so the user never has to press ⌘S.
    private func scheduleAutosave() {
        guard autoSaveEnabled, currentURL != nil else { return }
        autosaveItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isDirty, self.currentURL != nil else { return }
            self.performSave { _ in }
        }
        autosaveItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    func setAutoSave(_ enabled: Bool) {
        autoSaveEnabled = enabled
        defaults.set(enabled, forKey: "ouro.autosave")
        if enabled, isDirty { scheduleAutosave() }
    }

    func setTextScale(_ value: Double) {
        zoom = min(max(value, 0.7), 2.0)
        defaults.set(zoom, forKey: "ouro.zoom")
        bridge?.setZoom(zoom)
    }

    // MARK: - File operations

    func newDocument() {
        confirmDiscard { [weak self] in
            guard let self else { return }
            self.currentURL = nil
            self.lastLoadedContent = nil
            self.stopWatching()
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
                self.lastLoadedContent = text
                self.pushMarkdown(text)
                self.isDirty = false
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                self.refreshFolder()
                self.startWatching()
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
        lastLoadedContent = text
        pushMarkdown(text)
        isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshFolder()
        startWatching()
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
                // Record what we're about to put on disk before writing, so the
                // file watcher recognizes the resulting change as our own.
                self.lastLoadedContent = markdown
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                self.bridge?.markSaved()
                self.isDirty = false
                self.startWatching()
                self.onChromeUpdate?()
                completion(true)
            } catch {
                self.presentError("Could not save \(url.lastPathComponent)", error)
                completion(false)
            }
        }
    }

    // MARK: - Live external reload

    /// Begin watching the current file for external edits (e.g. an agent
    /// rewriting it). Safe to call repeatedly; re-targets the current URL.
    private func startWatching() {
        stopWatching()
        guard let url = currentURL else { return }
        let watcher = FileWatcher(url: url) { [weak self] in
            self?.handleExternalChange()
        }
        fileWatcher = watcher
        watcher.start()
    }

    private func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Called on the main queue when the open file changes on disk.
    private func handleExternalChange() {
        guard let url = currentURL else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else {
            // File was deleted or moved out from under us — keep the buffer as
            // an unsaved copy rather than blanking the reader's view.
            isDirty = true
            onChromeUpdate?()
            return
        }
        // Our own save (or no real change) — nothing to do.
        guard disk != lastLoadedContent else { return }

        if isDirty {
            presentExternalChangeConflict(diskContent: disk, url: url)
        } else {
            lastLoadedContent = disk
            bridge?.reloadMarkdown(disk)   // preserves scroll position
        }
    }

    /// The file changed on disk while the reader had unsaved edits — never
    /// clobber silently; let them choose.
    private func presentExternalChangeConflict(diskContent: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) changed on disk"
        alert.informativeText = "This file was modified by another program while you had unsaved changes. Reload the new version (discarding your edits), or keep your edits?"
        alert.addButton(withTitle: "Reload from Disk")
        alert.addButton(withTitle: "Keep My Edits")
        let response = alert.runModal()
        // Either way, treat the on-disk content as the new baseline so we don't
        // re-prompt for the same external change.
        lastLoadedContent = diskContent
        if response == .alertFirstButtonReturn {
            bridge?.reloadMarkdown(diskContent)
            isDirty = false
            onChromeUpdate?()
        }
        // "Keep My Edits": leave the dirty buffer untouched; a later save wins.
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
        onChromeUpdate?()
    }

    private func applyThemeToEditor() {
        // Light themes use the bundled "github" hljs base; the editor CSS then
        // overrides token colors to Typora's CodeMirror (cm-s-inner) palette.
        let codeTheme = theme.uiMode == "dark" ? "github-dark" : "github"
        bridge?.applyTheme(uiMode: theme.uiMode, css: theme.editorCSS, codeTheme: codeTheme)
    }

    func setMode(_ newMode: String) {
        mode = newMode
        bridge?.setMode(newMode)
    }

    func toggleOutline() {
        showOutline.toggle()
        bridge?.setOutline(showOutline)
    }

    func toggleFocusMode() {
        focusMode.toggle()
        bridge?.setFocusMode(focusMode)
    }

    func toggleTypewriter() {
        typewriter.toggle()
        bridge?.setTypewriter(typewriter)
    }

    // MARK: - Sidebar

    func setSidebarMode(_ mode: SidebarMode) {
        sidebarMode = mode
        defaults.set(mode.rawValue, forKey: "ouro.sidebarMode")
    }

    func setSidebarVisible(_ visible: Bool) {
        sidebarVisible = visible
        defaults.set(visible, forKey: "ouro.sidebar")
    }

    func updateOutline(_ items: [OutlineItem]) {
        outlineItems = items
    }

    func selectHeading(index: Int) {
        bridge?.scrollToHeading(index)
    }

    func setActiveHeading(_ index: Int) { activeHeadingIndex = index }

    /// Flat heading list nested into a tree by heading level (for a collapsible
    /// outline). Stack-based: each heading attaches under the nearest shallower one.
    var outlineTree: [OutlineNode] {
        OutlineNode.build(from: outlineItems)
    }

    /// Headings matching the outline filter (case-insensitive substring).
    var filteredOutline: [OutlineItem] {
        let q = outlineFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return outlineItems }
        return outlineItems.filter { $0.text.lowercased().contains(q) }
    }

    func openFolderItem(_ item: FolderItem) {
        guard item.url != currentURL else { return }
        open(url: item.url)
    }

    /// Opens a file from the folder browser (keeps the mounted folder intact).
    func openFile(_ url: URL) {
        guard url != currentURL else { return }
        open(url: url)
    }

    /// Creates a new empty markdown file in the mounted folder and opens it.
    func newFileInMountedFolder() {
        guard let folder = mountedFolder else { newDocument(); return }
        var name = "Untitled.md"
        var counter = 1
        var url = folder.appendingPathComponent(name)
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            name = "Untitled \(counter).md"
            url = folder.appendingPathComponent(name)
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            open(url: url)
        } catch {
            presentError("Could not create \(name)", error)
        }
    }

    // MARK: - Folder browser (Open Folder)

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }

    func openFolder(_ url: URL) {
        mountedFolder = url
        sidebarMode = .files
        sidebarVisible = true
        defaults.set(true, forKey: "ouro.sidebar")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        startFolderWatching()
        rescanFolder()
        onChromeUpdate?()
    }

    func closeFolder() {
        mountedFolder = nil
        folderTree = []
        folderFlat = []
        folderWatcher?.stop()
        folderWatcher = nil
        onChromeUpdate?()
    }

    /// Auto-mounts a file's parent folder the first time a file is opened, so
    /// the sidebar is populated without an explicit Open Folder.
    private func ensureFolderMounted(for fileURL: URL) {
        guard mountedFolder == nil else { rescanFolder(); return }
        let parent = fileURL.deletingLastPathComponent()
        mountedFolder = parent
        startFolderWatching()
        rescanFolder()
    }

    func setFolderSort(_ sort: FolderSort) {
        guard sort != folderSort else { return }
        folderSort = sort
        rescanFolder()
    }

    func toggleFolderView() { useTreeView.toggle() }

    private func startFolderWatching() {
        folderWatcher?.stop()
        guard let folder = mountedFolder else { return }
        let watcher = FolderWatcher(url: folder) { [weak self] in self?.rescanFolder() }
        folderWatcher = watcher
        watcher.start()
    }

    /// Re-scans the mounted folder off the main thread, then publishes.
    func rescanFolder() {
        guard let folder = mountedFolder else { folderTree = []; folderFlat = []; return }
        let sort = folderSort
        folderScanQueue.async { [weak self] in
            let tree = FolderScanner.tree(at: folder, sort: sort)
            let flat = FolderScanner.flatList(at: folder, sort: sort)
            DispatchQueue.main.async {
                guard let self, self.mountedFolder == folder else { return }
                self.folderTree = tree
                self.folderFlat = flat
            }
        }
    }

    /// Files matching the current filename filter (fuzzy: space-separated terms
    /// matched as an ordered subsequence — Typora's quick-find behavior).
    var filteredFolderFiles: [FolderNode] {
        let query = folderFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return folderFlat }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return folderFlat.filter { node in
            let name = node.name.lowercased()
            var idx = name.startIndex
            for term in terms {
                guard let r = name.range(of: term, range: idx..<name.endIndex) else { return false }
                idx = r.upperBound
            }
            return true
        }
    }

    var mountedFolderName: String { mountedFolder?.lastPathComponent ?? "Open Folder…" }

    func refreshFolder() {
        // Folder browser now tracks an explicitly-mounted folder; opening a file
        // auto-mounts its parent the first time so the sidebar isn't empty.
        if let url = currentURL { ensureFolderMounted(for: url) }
    }

    // MARK: - Find & Replace

    func setFindQuery(_ query: String) {
        findQuery = query
        findCurrent()
    }

    private func findCurrent() { bridge?.find(findQuery, backward: false, caseSensitive: findCaseSensitive, wholeWord: findWholeWord, regexp: findRegexp) }
    func findNext() { bridge?.find(findQuery, backward: false, caseSensitive: findCaseSensitive, wholeWord: findWholeWord, regexp: findRegexp) }
    func findPrev() { bridge?.find(findQuery, backward: true, caseSensitive: findCaseSensitive, wholeWord: findWholeWord, regexp: findRegexp) }

    func showFind() { findVisible = true; replaceVisible = false }
    func showReplace() { findVisible = true; replaceVisible = true }
    func closeFind() { findVisible = false; replaceVisible = false; findStatus = ""; bridge?.clearFind() }
    func toggleFind() { findVisible.toggle(); if !findVisible { closeFind() } }

    func replaceNext() {
        guard !findQuery.isEmpty else { return }
        bridge?.replace(findQuery, with: replaceText, all: false, caseSensitive: findCaseSensitive, wholeWord: findWholeWord, regexp: findRegexp) { [weak self] n in
            self?.findStatus = n > 0 ? "Replaced 1" : "Not found"
        }
    }

    func replaceAll() {
        guard !findQuery.isEmpty else { return }
        bridge?.replace(findQuery, with: replaceText, all: true, caseSensitive: findCaseSensitive, wholeWord: findWholeWord, regexp: findRegexp) { [weak self] n in
            self?.findStatus = "Replaced \(n) occurrence\(n == 1 ? "" : "s")"
        }
    }

    func zoomIn() { setTextScale(zoom + 0.1) }
    func zoomOut() { setTextScale(zoom - 0.1) }
    func actualSize() { setTextScale(1.0) }
    func format(_ command: String) { bridge?.execCommand(command) }

    func printDocument() { bridge?.printDocument() }

    func copyAsMarkdown() {
        bridge?.getMarkdown { md in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(md, forType: .string)
        }
    }

    func copyAsHTML() {
        bridge?.getHTML { html in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(html, forType: .string)
        }
    }

    func pasteAsPlainText() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        bridge?.insertText(text)
    }

    // MARK: - Folder content search (Search tab)

    func runFolderSearch() {
        let query = searchQuery
        searchResults = []
        guard let folder = mountedFolder ?? currentURL?.deletingLastPathComponent(),
              !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searching = false
            contentSearcher.cancel()
            return
        }
        if mountedFolder == nil { mountedFolder = folder }
        searching = true
        contentSearcher.search(query, in: folder,
                               caseSensitive: searchCaseSensitive, wholeWord: searchWholeWord, regexp: searchRegexp,
                               onResult: { [weak self] result in self?.appendSearchResult(result) },
                               onComplete: { [weak self] in self?.searching = false })
    }

    private func appendSearchResult(_ result: SearchResult) {
        searchResults.append(result)
        searchResults.sort { a, b in
            if a.nameMatched != b.nameMatched { return a.nameMatched }
            if a.count != b.count { return a.count > b.count }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func openSearchResult(_ url: URL) { openFile(url) }

    // MARK: - Helpers

    private func pushMarkdown(_ markdown: String) {
        if isReady {
            bridge?.setDocBase(currentURL?.deletingLastPathComponent().path)
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
