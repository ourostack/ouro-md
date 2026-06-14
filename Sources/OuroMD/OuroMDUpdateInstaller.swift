import CryptoKit
import Foundation

struct OuroMDUpdateInstaller: Sendable {
    var bundleIdentifier: String
    var currentVersion: String
    private let dataLoader: @Sendable (URL) async throws -> Data
    private let processRunner: @Sendable (ProcessInvocation) async throws -> ProcessResult

    struct Staged: Equatable, Sendable {
        var appURL: URL
        var stagingRoot: URL
        var version: String
    }

    struct ProcessInvocation: Equatable, Sendable {
        var executablePath: String
        var arguments: [String]
    }

    struct ProcessResult: Equatable, Sendable {
        var status: Int32
        var stderr: String

        static let success = ProcessResult(status: 0, stderr: "")
    }

    enum InstallError: LocalizedError, Equatable, Sendable {
        case download(String)
        case manifestDecode(String)
        case verification(OuroMDUpdateVerification.Failure)
        case unzipFailed(String)
        case missingStagedApp
        case stagedIdentityMismatch(String)
        case codesignFailed(String)

        var errorDescription: String? {
            switch self {
            case let .download(message):
                return "Download failed: \(message)"
            case let .manifestDecode(message):
                return "Could not read the release manifest: \(message)"
            case let .verification(failure):
                return failure.errorDescription
            case let .unzipFailed(message):
                return "Could not expand the downloaded archive: \(message)"
            case .missingStagedApp:
                return "The downloaded archive did not contain Ouro MD.app."
            case let .stagedIdentityMismatch(message):
                return "The downloaded app failed its identity check: \(message)"
            case let .codesignFailed(message):
                return "The downloaded app failed its code-signature check: \(message)"
            }
        }
    }

    init(
        bundleIdentifier: String = OuroMDRelease.bundleIdentifier,
        currentVersion: String = OuroMDRelease.version,
        dataLoader: (@Sendable (URL) async throws -> Data)? = nil,
        processRunner: @escaping @Sendable (ProcessInvocation) async throws -> ProcessResult = OuroMDUpdateInstaller.defaultProcessRunner
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.currentVersion = currentVersion
        let userAgent = "OuroMD/\(currentVersion)"
        self.dataLoader = dataLoader ?? { url in
            try await Self.defaultData(from: url, userAgent: userAgent)
        }
        self.processRunner = processRunner
    }

    @discardableResult
    func stage(
        plan: OuroMDUpdatePlan,
        progress: @Sendable (String) async -> Void
    ) async throws -> Staged {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ouro-md-update-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            await progress("Downloading release manifest...")
            let manifestData = try await load(plan.manifestURL)
            let manifest: OuroMDUpdateManifest
            do {
                manifest = try JSONDecoder().decode(OuroMDUpdateManifest.self, from: manifestData)
            } catch {
                throw InstallError.manifestDecode(error.localizedDescription)
            }

            await progress("Downloading \(plan.archiveName)...")
            let archiveData = try await load(plan.archiveURL)
            let archiveURL = root.appendingPathComponent(plan.archiveName)
            try archiveData.write(to: archiveURL)

            await progress("Verifying download...")
            let sha = Self.sha256Hex(archiveData)
            if let failure = OuroMDUpdateVerification.verify(
                manifest: manifest,
                downloadedArchiveName: plan.archiveName,
                downloadedSHA256: sha,
                downloadedBytes: archiveData.count,
                expectedBundleIdentifier: bundleIdentifier,
                currentVersion: currentVersion
            ) {
                throw InstallError.verification(failure)
            }

            await progress("Expanding update...")
            let extractRoot = root.appendingPathComponent("extract", isDirectory: true)
            try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)
            let unzip = try await processRunner(
                ProcessInvocation(
                    executablePath: "/usr/bin/ditto",
                    arguments: ["-x", "-k", archiveURL.path, extractRoot.path]
                )
            )
            guard unzip.status == 0 else {
                throw InstallError.unzipFailed(unzip.stderr.isEmpty ? "ditto exited \(unzip.status)" : unzip.stderr)
            }

            let appURL = extractRoot.appendingPathComponent("Ouro MD.app", isDirectory: true)
            guard fileManager.fileExists(atPath: appURL.path) else {
                throw InstallError.missingStagedApp
            }

            try verifyStagedApp(appURL, manifest: manifest)

            await progress("Checking signature...")
            let codesign = try await processRunner(
                ProcessInvocation(
                    executablePath: "/usr/bin/codesign",
                    arguments: ["--verify", "--deep", "--strict", appURL.path]
                )
            )
            guard codesign.status == 0 else {
                throw InstallError.codesignFailed(
                    codesign.stderr.isEmpty ? "codesign exited \(codesign.status)" : codesign.stderr
                )
            }

            return Staged(appURL: appURL, stagingRoot: root, version: manifest.version)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    static func applyAndRelaunch(staged: Staged, destinationBundle: URL, relaunch: Bool = true) {
        let script = applyScript(
            staged: staged,
            destinationBundle: destinationBundle,
            relaunch: relaunch,
            waitingForPID: ProcessInfo.processInfo.processIdentifier
        )
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()
    }

    static func applyOnQuit(staged: Staged, destinationBundle: URL) {
        applyAndRelaunch(staged: staged, destinationBundle: destinationBundle, relaunch: false)
    }

    static func applyScript(
        staged: Staged,
        destinationBundle: URL,
        relaunch: Bool,
        waitingForPID pid: Int32
    ) -> String {
        let dest = destinationBundle.path
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        let reopen = relaunch ? "/usr/bin/open \"$DEST\"\n" : ""
        return """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        DEST=\(shellQuoted(dest))
        STAGED=\(shellQuoted(staged.appURL.path))
        STAGING_ROOT=\(shellQuoted(staged.stagingRoot.path))
        reopen_if_safe() {
          [ -d "$DEST" ] && \(reopen.isEmpty ? ":" : "/usr/bin/open \"$DEST\"")
        }
        restore_backup() {
          if [ -d "$DEST.update-bak" ]; then
            /bin/rm -rf "$DEST"
            if ! /bin/mv "$DEST.update-bak" "$DEST"; then
              exit 1
            fi
            if [ ! -d "$DEST" ]; then
              exit 1
            fi
          fi
        }
        /bin/rm -rf "$DEST.update-new" "$DEST.update-bak"
        if ! /usr/bin/ditto "$STAGED" "$DEST.update-new"; then
          reopen_if_safe
          exit 1
        fi
        if [ -e "$DEST" ] && ! /bin/mv "$DEST" "$DEST.update-bak"; then
          /bin/rm -rf "$DEST.update-new"
          reopen_if_safe
          exit 1
        fi
        if /bin/mv "$DEST.update-new" "$DEST"; then
          if [ ! -d "$DEST" ]; then
            restore_backup
            reopen_if_safe
            exit 1
          fi
          /bin/rm -rf "$DEST.update-bak"
        else
          restore_backup
          reopen_if_safe
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        \(shellQuoted(lsregister)) -f "$DEST" 2>/dev/null || true
        reopen_if_safe
        /bin/rm -rf "$STAGING_ROOT" 2>/dev/null
        """
    }

    private func load(_ url: URL) async throws -> Data {
        do {
            return try await dataLoader(url)
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.download("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func verifyStagedApp(_ appURL: URL, manifest: OuroMDUpdateManifest) throws {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        let info = try PropertyListSerialization.propertyList(from: infoData, options: [], format: nil) as? [String: Any]
        let stagedBundleID = info?["CFBundleIdentifier"] as? String
        let stagedVersion = info?["CFBundleShortVersionString"] as? String

        guard stagedBundleID == manifest.bundleIdentifier else {
            throw InstallError.stagedIdentityMismatch(
                "bundle id \(stagedBundleID ?? "nil") != manifest \(manifest.bundleIdentifier)"
            )
        }
        guard stagedVersion == manifest.version else {
            throw InstallError.stagedIdentityMismatch(
                "version \(stagedVersion ?? "nil") != manifest \(manifest.version)"
            )
        }
    }

    private static func defaultData(from url: URL, userAgent: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.download("\(url.lastPathComponent) returned HTTP \(http.statusCode)")
        }
        return data
    }

    private static let defaultProcessRunner: @Sendable (ProcessInvocation) async throws -> ProcessResult = { invocation in
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: invocation.executablePath)
                process.arguments = invocation.arguments
                let errorPipe = Pipe()
                process.standardError = errorPipe
                process.standardOutput = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let stderr = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: ProcessResult(status: process.terminationStatus, stderr: stderr))
            }
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
