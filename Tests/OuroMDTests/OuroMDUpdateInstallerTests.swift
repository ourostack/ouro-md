import CryptoKit
import Foundation
import XCTest
@testable import OuroMD

final class OuroMDUpdateInstallerTests: XCTestCase {
    private let archiveData = Data("fake archive bytes".utf8)

    func testStageSucceedsAfterManifestArchiveExtractedBundleAndCodesignVerify() async throws {
        let harness = InstallerHarness()
        let manifest = manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count)
        let installer = harness.installer(manifestData: manifest, archiveData: archiveData) { invocation in
            if invocation.executablePath == "/usr/bin/ditto" {
                try self.writeFakeApp(
                    under: URL(fileURLWithPath: invocation.arguments[3]),
                    bundleIdentifier: "org.ourostack.ouro-md",
                    version: "0.10.0"
                )
            }
            return .success
        }

        let staged = try await installer.stage(plan: updatePlan(), progress: { _ in })

        XCTAssertEqual(staged.version, "0.10.0")
        XCTAssertEqual(staged.appURL.lastPathComponent, "Ouro MD.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.appURL.path))
        XCTAssertEqual(harness.invocations.map(\.executablePath), ["/usr/bin/ditto", "/usr/bin/codesign"])
        XCTAssertEqual(harness.invocations[0].arguments.prefix(2), ["-x", "-k"])
        XCTAssertEqual(harness.invocations[1].arguments.suffix(2), ["--strict", staged.appURL.path])
    }

    func testStageThrowsOnManifestDecodeFailure() async {
        let installer = InstallerHarness().installer(
            manifestData: Data("not-json".utf8),
            archiveData: archiveData
        )

        await assertStageThrows(.manifestDecode) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        }
    }

    func testStageWrapsGenericDataLoaderFailureAsDownloadError() async {
        let installer = OuroMDUpdateInstaller(
            bundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0",
            dataLoader: { _ in throw NSError(domain: "loader", code: 7) },
            processRunner: { _ in .success }
        )

        await assertStageThrows(.download) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            guard case let .download(message) = error else {
                XCTFail("Expected download error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Ouro-MD-0.10.0.manifest.json"))
        }
    }

    func testStagePreservesInstallerErrorFromDataLoader() async {
        let installer = OuroMDUpdateInstaller(
            bundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0",
            dataLoader: { _ in throw OuroMDUpdateInstaller.InstallError.download("explicit") },
            processRunner: { _ in .success }
        )

        await assertStageThrows(.download) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(error, .download("explicit"))
        }
    }

    func testStageThrowsOnSHAMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: "deadbeef", bytes: archiveData.count),
            archiveData: archiveData
        )

        await assertStageThrows(.verification) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(
                error,
                .verification(.sha256Mismatch(expected: "deadbeef", got: sha256Hex(self.archiveData)))
            )
        }
    }

    func testStageThrowsOnByteCountMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count + 1),
            archiveData: archiveData
        )

        await assertStageThrows(.verification) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(
                error,
                .verification(.byteCountMismatch(expected: self.archiveData.count + 1, got: self.archiveData.count))
            )
        }
    }

    func testStageThrowsOnArchiveNameMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(
                sha: sha256Hex(archiveData),
                bytes: archiveData.count,
                archive: "Different.zip"
            ),
            archiveData: archiveData
        )

        await assertStageThrows(.verification) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(
                error,
                .verification(.archiveNameMismatch(expected: "Different.zip", got: "Ouro-MD-0.10.0.zip"))
            )
        }
    }

    func testStageThrowsOnBundleIdentifierMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(
                sha: sha256Hex(archiveData),
                bytes: archiveData.count,
                bundleIdentifier: "com.example.bad"
            ),
            archiveData: archiveData
        )

        await assertStageThrows(.verification) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(
                error,
                .verification(.bundleIdentifierMismatch(expected: "org.ourostack.ouro-md", got: "com.example.bad"))
            )
        }
    }

    func testStageThrowsOnNonNewerVersion() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(
                sha: sha256Hex(archiveData),
                bytes: archiveData.count,
                version: "0.9.0"
            ),
            archiveData: archiveData
        )

        await assertStageThrows(.verification) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(
                error,
                .verification(.notNewerThanCurrent(current: "0.9.0", candidate: "0.9.0"))
            )
        }
    }

    func testStageThrowsOnMissingStagedApp() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count),
            archiveData: archiveData,
            processRunner: { _ in .success }
        )

        await assertStageThrows(.missingStagedApp) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        }
    }

    func testStageThrowsOnUnzipFailureWithExitStatusFallback() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count),
            archiveData: archiveData,
            processRunner: { invocation in
                if invocation.executablePath == "/usr/bin/ditto" {
                    return OuroMDUpdateInstaller.ProcessResult(status: 12, stderr: "")
                }
                return .success
            }
        )

        await assertStageThrows(.unzipFailed) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        } inspect: { error in
            XCTAssertEqual(error, .unzipFailed("ditto exited 12"))
        }
    }

    func testStageThrowsOnStagedBundleIdentifierMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count),
            archiveData: archiveData
        ) { invocation in
            if invocation.executablePath == "/usr/bin/ditto" {
                try self.writeFakeApp(
                    under: URL(fileURLWithPath: invocation.arguments[3]),
                    bundleIdentifier: "com.example.bad",
                    version: "0.10.0"
                )
            }
            return .success
        }

        await assertStageThrows(.stagedIdentityMismatch) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        }
    }

    func testStageThrowsOnStagedVersionMismatch() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count),
            archiveData: archiveData
        ) { invocation in
            if invocation.executablePath == "/usr/bin/ditto" {
                try self.writeFakeApp(
                    under: URL(fileURLWithPath: invocation.arguments[3]),
                    bundleIdentifier: "org.ourostack.ouro-md",
                    version: "0.9.9"
                )
            }
            return .success
        }

        await assertStageThrows(.stagedIdentityMismatch) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        }
    }

    func testStageThrowsOnCodesignFailure() async {
        let installer = InstallerHarness().installer(
            manifestData: manifestData(sha: sha256Hex(archiveData), bytes: archiveData.count),
            archiveData: archiveData
        ) { invocation in
            if invocation.executablePath == "/usr/bin/ditto" {
                try self.writeFakeApp(
                    under: URL(fileURLWithPath: invocation.arguments[3]),
                    bundleIdentifier: "org.ourostack.ouro-md",
                    version: "0.10.0"
                )
                return .success
            }
            return OuroMDUpdateInstaller.ProcessResult(status: 1, stderr: "not signed")
        }

        await assertStageThrows(.codesignFailed) {
            try await installer.stage(plan: updatePlan(), progress: { _ in })
        }
    }

    func testApplyScriptFailsFastAroundBackupInstallAndRollback() {
        let staged = OuroMDUpdateInstaller.Staged(
            appURL: URL(fileURLWithPath: "/tmp/staged/Ouro MD.app"),
            stagingRoot: URL(fileURLWithPath: "/tmp/staged"),
            version: "0.10.0"
        )

        let script = OuroMDUpdateInstaller.applyScript(
            staged: staged,
            destinationBundle: URL(fileURLWithPath: "/Applications/Ouro MD.app"),
            relaunch: true,
            waitingForPID: 1234
        )

        XCTAssertTrue(script.contains("if [ -e \"$DEST\" ] && ! /bin/mv \"$DEST\" \"$DEST.update-bak\"; then"))
        XCTAssertTrue(script.contains("exit 1"))
        XCTAssertTrue(script.contains("if /bin/mv \"$DEST.update-new\" \"$DEST\"; then"))
        XCTAssertTrue(script.contains("restore_backup()"))
        XCTAssertTrue(script.contains("if ! /bin/mv \"$DEST.update-bak\" \"$DEST\"; then"))
        XCTAssertTrue(script.contains("if [ ! -d \"$DEST\" ]; then"))
    }

    func testApplyScriptDoesNotDeleteBackupBeforeDestinationShapeIsProven() throws {
        let script = OuroMDUpdateInstaller.applyScript(
            staged: OuroMDUpdateInstaller.Staged(
                appURL: URL(fileURLWithPath: "/tmp/staged/Ouro MD.app"),
                stagingRoot: URL(fileURLWithPath: "/tmp/staged"),
                version: "0.10.0"
            ),
            destinationBundle: URL(fileURLWithPath: "/Applications/Ouro MD.app"),
            relaunch: false,
            waitingForPID: 999_999
        )

        let staleBackupCheck = try XCTUnwrap(script.range(of: "if [ -e \"$DEST.update-bak\" ]; then"))
        let staleDestinationGuard = try XCTUnwrap(script.range(
            of: "if [ -d \"$DEST\" ]; then",
            range: staleBackupCheck.upperBound..<script.endIndex
        ))
        let staleBackupRemoval = try XCTUnwrap(script.range(
            of: "/bin/rm -rf \"$DEST.update-bak\"",
            range: staleDestinationGuard.upperBound..<script.endIndex
        ))
        let installDestinationGuard = try XCTUnwrap(script.range(
            of: "if [ ! -d \"$DEST\" ]; then",
            range: staleBackupRemoval.upperBound..<script.endIndex
        ))
        let successBackupRemoval = try XCTUnwrap(script.range(
            of: "/bin/rm -rf \"$DEST.update-bak\"",
            range: installDestinationGuard.upperBound..<script.endIndex
        ))

        XCTAssertLessThan(staleDestinationGuard.lowerBound, staleBackupRemoval.lowerBound)
        XCTAssertLessThan(installDestinationGuard.lowerBound, successBackupRemoval.lowerBound)
        XCTAssertFalse(script.contains("/bin/rm -rf \"$DEST.update-new\" \"$DEST.update-bak\""))
        XCTAssertFalse(script.contains("/bin/mv \"$DEST.update-bak\" \"$DEST\" 2>/dev/null || true"))
    }

    func testApplyScriptRestoresStaleBackupBeforeTryingNewInstall() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-apply-stale-backup-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = root.appendingPathComponent("missing-staged/Ouro MD.app", isDirectory: true)
        let destApp = root.appendingPathComponent("installed/Ouro MD.app", isDirectory: true)
        let backupApp = URL(fileURLWithPath: destApp.path + ".update-bak", isDirectory: true)
        try FileManager.default.createDirectory(at: backupApp, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: backupApp.appendingPathComponent("old.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let script = OuroMDUpdateInstaller.applyScript(
            staged: OuroMDUpdateInstaller.Staged(appURL: stagedApp, stagingRoot: root, version: "0.10.0"),
            destinationBundle: destApp,
            relaunch: false,
            waitingForPID: 999_999
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()

        XCTAssertNotEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destApp.appendingPathComponent("old.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupApp.path))
    }

    func testApplyScriptRunsInTemporaryDirectoryWithoutNestingUpdatedApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ouro-apply-script-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = root.appendingPathComponent("staged/Ouro MD.app", isDirectory: true)
        let destApp = root.appendingPathComponent("installed/Ouro MD.app", isDirectory: true)
        try FileManager.default.createDirectory(at: stagedApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destApp, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: stagedApp.appendingPathComponent("new.txt"))
        try Data("old".utf8).write(to: destApp.appendingPathComponent("old.txt"))
        defer { try? FileManager.default.removeItem(at: root) }

        let script = OuroMDUpdateInstaller.applyScript(
            staged: OuroMDUpdateInstaller.Staged(
                appURL: stagedApp,
                stagingRoot: root.appendingPathComponent("staged", isDirectory: true),
                version: "0.10.0"
            ),
            destinationBundle: destApp,
            relaunch: false,
            waitingForPID: 999_999
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destApp.appendingPathComponent("new.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destApp.appendingPathComponent("Ouro MD.app").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destApp.path + ".update-bak"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("staged").path))
    }

    func testInstallErrorDescriptionsAreUserReadable() {
        let errors: [(OuroMDUpdateInstaller.InstallError, String)] = [
            (.download("net down"), "Download failed: net down"),
            (.manifestDecode("bad json"), "Could not read the release manifest: bad json"),
            (
                .verification(.sha256Mismatch(expected: "a", got: "b")),
                "Downloaded archive failed its SHA-256 integrity check."
            ),
            (.unzipFailed("ditto exited 12"), "Could not expand the downloaded archive: ditto exited 12"),
            (.missingStagedApp, "The downloaded archive did not contain Ouro MD.app."),
            (
                .stagedIdentityMismatch("bundle id bad"),
                "The downloaded app failed its identity check: bundle id bad"
            ),
            (.codesignFailed("unsigned"), "The downloaded app failed its code-signature check: unsigned"),
        ]

        for (error, description) in errors {
            XCTAssertEqual(error.errorDescription, description)
        }
    }

    private func updatePlan() -> OuroMDUpdatePlan {
        OuroMDUpdatePlan(
            version: "0.10.0",
            archiveURL: URL(string: "https://example.test/Ouro-MD-0.10.0.zip")!,
            archiveName: "Ouro-MD-0.10.0.zip",
            manifestURL: URL(string: "https://example.test/Ouro-MD-0.10.0.manifest.json")!
        )
    }

    private func manifestData(
        sha: String,
        bytes: Int,
        bundleIdentifier: String = "org.ourostack.ouro-md",
        version: String = "0.10.0",
        archive: String = "Ouro-MD-0.10.0.zip"
    ) -> Data {
        Data("""
        {
          "appName": "Ouro MD",
          "bundleIdentifier": "\(bundleIdentifier)",
          "version": "\(version)",
          "build": "\(version)",
          "archive": "\(archive)",
          "sha256": "\(sha)",
          "bytes": \(bytes)
        }
        """.utf8)
    }

    private func writeFakeApp(under root: URL, bundleIdentifier: String, version: String) throws {
        let contents = root.appendingPathComponent("Ouro MD.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum ExpectedError {
        case download
        case manifestDecode
        case verification
        case unzipFailed
        case missingStagedApp
        case stagedIdentityMismatch
        case codesignFailed
    }

    private func assertStageThrows(
        _ expected: ExpectedError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void,
        inspect: (OuroMDUpdateInstaller.InstallError) -> Void = { _ in }
    ) async {
        do {
            try await body()
            XCTFail("Expected stage to throw.", file: file, line: line)
        } catch let error as OuroMDUpdateInstaller.InstallError {
            switch (expected, error) {
            case (.download, .download),
                 (.manifestDecode, .manifestDecode),
                 (.verification, .verification),
                 (.unzipFailed, .unzipFailed),
                 (.missingStagedApp, .missingStagedApp),
                 (.stagedIdentityMismatch, .stagedIdentityMismatch),
                 (.codesignFailed, .codesignFailed):
                inspect(error)
            default:
                XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Unexpected non-installer error: \(error)", file: file, line: line)
        }
    }
}

private final class InstallerHarness {
    typealias ProcessInvocation = OuroMDUpdateInstaller.ProcessInvocation
    typealias ProcessResult = OuroMDUpdateInstaller.ProcessResult

    private(set) var invocations: [ProcessInvocation] = []

    func installer(
        manifestData: Data,
        archiveData: Data,
        processRunner: @escaping @Sendable (ProcessInvocation) async throws -> ProcessResult = { _ in .success }
    ) -> OuroMDUpdateInstaller {
        OuroMDUpdateInstaller(
            bundleIdentifier: "org.ourostack.ouro-md",
            currentVersion: "0.9.0",
            dataLoader: { url in
                if url.path.hasSuffix(".manifest.json") { return manifestData }
                return archiveData
            },
            processRunner: { invocation in
                self.invocations.append(invocation)
                return try await processRunner(invocation)
            }
        )
    }
}
