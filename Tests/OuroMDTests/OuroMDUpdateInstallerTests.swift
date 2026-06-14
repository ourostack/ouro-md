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
        case manifestDecode
        case verification
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
            case (.manifestDecode, .manifestDecode),
                 (.verification, .verification),
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
