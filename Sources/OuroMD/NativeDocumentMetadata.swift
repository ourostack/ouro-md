import AppKit

/// AppKit owns the document controls; AppModel remains the only buffer,
/// autosave and unsaved-close owner.
@MainActor
final class NativeDocumentMetadata: NSDocument {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        super.init()
        synchronizeIdentity()
    }

    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { false }
    override var isDocumentEdited: Bool { false }

    func synchronizeIdentity() {
        guard let model else { return }
        fileType = model.currentURL?.pathExtension.lowercased() == "md"
            ? "net.daringfireball.markdown" : "public.plain-text"
        fileURL = model.currentURL
        if let url = fileURL {
            fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: "ouro-md", code: 23,
                      userInfo: [NSLocalizedDescriptionKey: "Document content must be saved through the live editor."])
    }

    override func move(to url: URL, completionHandler: ((Error?) -> Void)?) {
        guard let model else {
            completionHandler?(NSError(domain: "ouro-md", code: 24,
                                      userInfo: [NSLocalizedDescriptionKey: "The document window has closed."]))
            return
        }
        do {
            try model.moveCurrentFile(to: url)
            synchronizeIdentity()
            completionHandler?(nil)
        } catch {
            completionHandler?(error)
        }
    }

    override func save(to url: URL, ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard let model else {
            completionHandler(NSError(domain: "ouro-md", code: 24,
                                      userInfo: [NSLocalizedDescriptionKey: "The document window has closed."]))
            return
        }
        let finish: (Bool) -> Void = { [weak self] saved in
            if saved { self?.synchronizeIdentity() }
            completionHandler(saved ? nil : NSError(
                domain: "ouro-md", code: 25,
                userInfo: [NSLocalizedDescriptionKey: "The live editor could not save this document."]))
        }
        if url.standardizedFileURL == model.currentURL?.standardizedFileURL {
            model.performSave(completion: finish)
        } else {
            model.performSaveAs(to: url, completion: finish)
        }
    }
}
