import AppKit

/// AppKit owns the document controls; AppModel remains the only buffer,
/// autosave and unsaved-close owner.
@MainActor
final class NativeDocumentMetadata: NSDocument {
    private weak var model: AppModel?

    convenience init(model: AppModel) throws {
        if let url = model.currentURL {
            try self.init(contentsOf: url, ofType: url.pathExtension.lowercased() == "md"
                           ? "net.daringfireball.markdown" : "public.plain-text")
        } else {
            self.init()
        }
        self.model = model
        synchronizeIdentity()
    }

    override class var autosavesInPlace: Bool { true }
    override class var preservesVersions: Bool { false }
    override var isDocumentEdited: Bool { false }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override func read(from data: Data, ofType typeName: String) throws {}

    func synchronizeIdentity() {
        guard let model else { return }
        fileType = model.currentURL?.pathExtension.lowercased() == "md"
            ? "net.daringfireball.markdown" : "public.plain-text"
        fileURL = model.currentURL
        if let url = fileURL {
            fileModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        refreshEditorLock()
    }

    override func data(ofType typeName: String) throws -> Data {
        throw NSError(domain: "ouro-md", code: 23,
                      userInfo: [NSLocalizedDescriptionKey: "Document content must be saved through the live editor."])
    }

    private func refreshEditorLock() {
        guard let model, let fileURL else { model?.setFileLocked(false); return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            model.setFileLocked((attributes[.immutable] as? Bool == true) ||
                                !FileManager.default.isWritableFile(atPath: fileURL.path))
        } catch {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                model.reportDocumentMetadataError(error)
            }
        }
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

    override func lock(completionHandler: ((Error?) -> Void)?) {
        guard let model else {
            completionHandler?(NSError(domain: "ouro-md", code: 24,
                                       userInfo: [NSLocalizedDescriptionKey: "The document window has closed."]))
            return
        }
        guard !model.writingToolsActive else {
            completionHandler?(NSError(domain: "ouro-md", code: 21,
                                       userInfo: [NSLocalizedDescriptionKey: "Wait for Writing Tools to finish before locking this document."]))
            return
        }
        if model.hasUnsavedWork {
            model.performSave { [weak self] saved in
                guard saved else {
                    completionHandler?(NSError(domain: "ouro-md", code: 25,
                                               userInfo: [NSLocalizedDescriptionKey: "Save your changes before locking this document."]))
                    return
                }
                self?.lockSavedFile(completionHandler: completionHandler)
            }
        } else {
            lockSavedFile(completionHandler: completionHandler)
        }
    }

    private func lockSavedFile(completionHandler: ((Error?) -> Void)?) {
        super.lock(completionHandler: { [weak self] (error: Error?) in
            if let self {
                (self.fileURL as NSURL?)?.removeAllCachedResourceValues()
                self.refreshEditorLock()
            }
            completionHandler?(error)
        })
    }

    override func unlock(completionHandler: ((Error?) -> Void)?) {
        super.unlock(completionHandler: { [weak self] (error: Error?) in
            if let self {
                if error == nil, let url = self.fileURL {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        if attributes[.immutable] as? Bool == true {
                            try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)
                        }
                    } catch {
                        completionHandler?(error)
                        return
                    }
                }
                (self.fileURL as NSURL?)?.removeAllCachedResourceValues()
                self.refreshEditorLock()
            }
            completionHandler?(error)
        })
    }

    override func save(to url: URL, ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard saveOperation == .saveOperation || saveOperation == .saveAsOperation ||
                saveOperation == .autosaveInPlaceOperation else {
            completionHandler(NSError(domain: "ouro-md", code: 27,
                                      userInfo: [NSLocalizedDescriptionKey: "Use Save As to save a copy of this document."]))
            return
        }
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
