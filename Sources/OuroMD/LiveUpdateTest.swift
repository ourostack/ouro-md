import Foundation
import OuroAppShellCore

/// Headless `--liveupdatetest`: given a temp destination containing an older
/// published Ouro MD.app, use the real update planner/installer to stage the
/// latest GitHub release and apply it to that destination.
final class LiveUpdateTester {
    private let fromVersion: String
    private let expectedToVersion: String?
    private let destinationBundle: URL

    init(fromVersion: String, expectedToVersion: String?, destinationBundle: URL) {
        self.fromVersion = fromVersion
        self.expectedToVersion = expectedToVersion
        self.destinationBundle = destinationBundle
    }

    func run() -> Never {
        Task {
            do {
                try await execute()
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("liveupdatetest: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }

    private func execute() async throws {
        let installedVersion = try bundleVersion(destinationBundle)
        guard installedVersion == fromVersion else {
            throw TestError("destination version \(installedVersion) did not match expected older version \(fromVersion)")
        }

        let checker = OuroAppShellCore.ReleaseUpdateChecker(
            configuration: OuroMDReleaseUpdate.configuration(currentVersion: fromVersion),
            dataLoader: Self.releaseFeedData
        )
        let snapshot = await checker.check()
        guard snapshot.status == .updateAvailable else {
            throw TestError("release feed did not report an update from \(fromVersion): \(snapshot.detail)")
        }
        guard let latest = snapshot.latestVersion else {
            throw TestError("release feed had no latestVersion")
        }
        if let expectedToVersion, latest != expectedToVersion {
            throw TestError("latest release \(latest) did not match expected \(expectedToVersion)")
        }

        let plan: OuroMDUpdatePlan
        switch OuroMDUpdatePlanner.plan(from: snapshot) {
        case let .success(value):
            plan = value
        case let .failure(error):
            throw TestError(error.errorDescription ?? error.localizedDescription)
        }

        let installer = OuroMDUpdateInstaller(currentVersion: fromVersion)
        let staged = try await installer.stage(plan: plan) { status in
            print(status)
        }
        defer { try? FileManager.default.removeItem(at: staged.stagingRoot) }

        let script = OuroMDUpdateInstaller.applyScript(
            staged: staged,
            destinationBundle: destinationBundle,
            relaunch: false,
            waitingForPID: 0
        )
        try runShell(script)

        let updatedVersion = try bundleVersion(destinationBundle)
        guard updatedVersion == latest else {
            throw TestError("updated destination version \(updatedVersion) did not match latest \(latest)")
        }
        print("live update path ok: \(fromVersion) -> \(updatedVersion)")
    }

    private func bundleVersion(_ bundle: URL) throws -> String {
        let infoURL = bundle.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        guard let version = plist?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            throw TestError("could not read CFBundleShortVersionString from \(infoURL.path)")
        }
        return version
    }

    private static let releaseFeedData: @Sendable (URLRequest) async throws -> Data = { input in
        var request = input
        request.setValue("OuroMD/live-update-test", forHTTPHeaderField: "User-Agent")
        if let token = ProcessInfo.processInfo.environment["GH_TOKEN"] ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TestError("release feed returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TestError("release feed returned HTTP \(http.statusCode)")
        }
        return data
    }

    private func runShell(_ script: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        task.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            throw TestError("apply script failed with status \(task.terminationStatus): \(text)")
        }
    }

    private struct TestError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
