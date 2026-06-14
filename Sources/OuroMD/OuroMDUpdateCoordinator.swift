import AppKit
import Foundation
import SwiftUI

enum OuroMDUpdatePrompt: Equatable {
    case installable(version: String)
    case upToDate(version: String)
    case failed(detail: String)

    var message: String {
        switch self {
        case let .installable(version):
            return "Ouro MD \(version) is available. Install it now and relaunch?"
        case let .upToDate(version):
            return "You're on the latest version (\(version))."
        case let .failed(detail):
            return detail
        }
    }

    var isInstallable: Bool {
        if case .installable = self { return true }
        return false
    }
}

@MainActor
final class OuroMDUpdateCoordinator: ObservableObject {
    static let autoUpdateEnabledDefaultsKey = "ouro.autoupdate.enabled"
    static let lastUpdateCheckAtDefaultsKey = "ouro.autoupdate.lastCheckAt"
    static let minimumAutoUpdateCheckInterval: TimeInterval = 3600

    @Published private(set) var releaseSnapshot: ReleaseUpdateSnapshot?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var installStatus: String?
    @Published private(set) var installError: String?
    @Published private(set) var stagedUpdateVersion: String?
    @Published var updatePrompt: OuroMDUpdatePrompt?
    @Published private(set) var autoUpdateEnabled: Bool {
        didSet {
            defaults.set(autoUpdateEnabled, forKey: Self.autoUpdateEnabledDefaultsKey)
        }
    }

    private let defaults: UserDefaults
    private let checker: @MainActor () async -> ReleaseUpdateSnapshot
    private let stageUpdate: @MainActor (OuroMDUpdatePlan, @escaping @Sendable (String) async -> Void) async throws -> OuroMDUpdateInstaller.Staged
    private let applyAndRelaunch: @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void
    private let applyOnQuit: @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void
    private let terminate: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private var pendingStagedUpdate: OuroMDUpdateInstaller.Staged?
    private var isApplyingManualUpdate = false
    private var autoUpdateCheckStartedThisSession = false

    init(
        defaults: UserDefaults = .standard,
        checker: @escaping @MainActor () async -> ReleaseUpdateSnapshot = {
            await ReleaseUpdateChecker().check()
        },
        stageUpdate: @escaping @MainActor (OuroMDUpdatePlan, @escaping @Sendable (String) async -> Void) async throws -> OuroMDUpdateInstaller.Staged = { plan, progress in
            try await OuroMDUpdateInstaller().stage(plan: plan, progress: progress)
        },
        applyAndRelaunch: @escaping @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void = {
            OuroMDUpdateInstaller.applyAndRelaunch(staged: $0, destinationBundle: $1)
        },
        applyOnQuit: @escaping @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void = {
            OuroMDUpdateInstaller.applyOnQuit(staged: $0, destinationBundle: $1)
        },
        terminate: @escaping @MainActor () -> Void = {
            NSApp.terminate(nil)
        },
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.checker = checker
        self.stageUpdate = stageUpdate
        self.applyAndRelaunch = applyAndRelaunch
        self.applyOnQuit = applyOnQuit
        self.terminate = terminate
        self.now = now
        self.autoUpdateEnabled = defaults.object(forKey: Self.autoUpdateEnabledDefaultsKey) as? Bool ?? true
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        autoUpdateEnabled = enabled
    }

    func checkForReleaseUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        releaseSnapshot = await checker()
    }

    func checkForUpdatesAndPromptInstall() async {
        await checkForReleaseUpdate()
        guard let snapshot = releaseSnapshot else {
            updatePrompt = .failed(detail: "Could not check for updates right now.")
            return
        }
        switch snapshot.status {
        case .updateAvailable:
            if snapshot.hasInstallableAssets, let version = snapshot.latestVersion {
                updatePrompt = .installable(version: version)
            } else {
                updatePrompt = .failed(detail: "A newer version is published but has no installable assets yet.")
            }
        case .current:
            updatePrompt = .upToDate(version: snapshot.currentVersion)
        case .unavailable:
            updatePrompt = .failed(detail: snapshot.detail)
        }
    }

    var updatePromptIsPresented: Binding<Bool> {
        Binding(
            get: { self.updatePrompt != nil },
            set: { newValue in
                if !newValue { self.updatePrompt = nil }
            }
        )
    }

    var updateBadgeText: String? {
        if let version = stagedUpdateVersion {
            return "Update \(version)"
        }
        if let snapshot = releaseSnapshot,
           snapshot.status == .updateAvailable,
           snapshot.hasInstallableAssets,
           let version = snapshot.latestVersion {
            return "Update \(version)"
        }
        return nil
    }

    func presentUpdatePrompt() {
        if let version = stagedUpdateVersion {
            updatePrompt = .installable(version: version)
        } else if let snapshot = releaseSnapshot,
                  snapshot.status == .updateAvailable,
                  snapshot.hasInstallableAssets,
                  let version = snapshot.latestVersion {
            updatePrompt = .installable(version: version)
        }
    }

    func runAutoUpdateCheckIfDue() async {
        guard !autoUpdateCheckStartedThisSession else { return }
        autoUpdateCheckStartedThisSession = true
        let currentDate = now()
        let lastCheck = defaults.object(forKey: Self.lastUpdateCheckAtDefaultsKey) as? Date
        guard OuroMDAutoUpdatePolicy.shouldCheck(
            now: currentDate,
            lastCheck: lastCheck,
            minimumInterval: Self.minimumAutoUpdateCheckInterval,
            enabled: autoUpdateEnabled
        ) else {
            return
        }
        defaults.set(currentDate, forKey: Self.lastUpdateCheckAtDefaultsKey)
        await checkForReleaseUpdate()
        guard autoUpdateEnabled,
              let snapshot = releaseSnapshot,
              snapshot.status == .updateAvailable,
              snapshot.hasInstallableAssets else {
            return
        }
        await stagePendingUpdate(from: snapshot)
    }

    func installReleaseUpdate(destinationBundle: URL = Bundle.main.bundleURL) async {
        guard !isInstalling else { return }
        if let staged = pendingStagedUpdate {
            installStatus = "Installing \(staged.version) and relaunching..."
            isApplyingManualUpdate = true
            applyAndRelaunch(staged, destinationBundle)
            terminate()
            return
        }

        guard let snapshot = releaseSnapshot else {
            installError = "Check for an update first."
            return
        }
        let plan: OuroMDUpdatePlan
        switch OuroMDUpdatePlanner.plan(from: snapshot) {
        case let .success(value):
            plan = value
        case let .failure(error):
            installError = error.errorDescription
            return
        }

        isInstalling = true
        installError = nil
        installStatus = "Starting..."
        do {
            let staged = try await stageUpdate(plan) { status in
                await MainActor.run { self.installStatus = status }
            }
            installStatus = "Installing \(staged.version) and relaunching..."
            isApplyingManualUpdate = true
            applyAndRelaunch(staged, destinationBundle)
            terminate()
        } catch {
            installError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            installStatus = nil
            isInstalling = false
        }
    }

    func applyStagedUpdateOnQuitIfNeeded(destinationBundle: URL = Bundle.main.bundleURL) {
        guard autoUpdateEnabled, !isApplyingManualUpdate, let staged = pendingStagedUpdate else {
            return
        }
        pendingStagedUpdate = nil
        stagedUpdateVersion = nil
        applyOnQuit(staged, destinationBundle)
    }

    private func stagePendingUpdate(from snapshot: ReleaseUpdateSnapshot) async {
        guard pendingStagedUpdate == nil else { return }
        guard case let .success(plan) = OuroMDUpdatePlanner.plan(from: snapshot) else { return }
        do {
            let staged = try await stageUpdate(plan) { _ in }
            pendingStagedUpdate = staged
            stagedUpdateVersion = staged.version
        } catch {
            // Background update staging is quiet; manual check/install reports errors.
        }
    }
}
