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
    private let stageUpdate: (OuroMDUpdatePlan, @escaping @Sendable (String) async -> Void) async throws -> OuroMDUpdateInstaller.Staged
    private let applyAndRelaunch: @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void
    private let applyOnQuit: @MainActor (OuroMDUpdateInstaller.Staged, URL) -> Void
    private let terminate: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private var inFlightCheck: InFlightCheck?
    private var pendingStagedUpdate: OuroMDUpdateInstaller.Staged?
    private var isApplyingManualUpdate = false
    private var autoUpdateCheckStartedThisSession = false

    private final class InFlightCheck {
        let task: Task<ReleaseUpdateSnapshot, Never>

        init(task: Task<ReleaseUpdateSnapshot, Never>) {
            self.task = task
        }
    }

    init(
        defaults: UserDefaults = .standard,
        checker: @escaping @MainActor () async -> ReleaseUpdateSnapshot = {
            await ReleaseUpdateChecker().check()
        },
        stageUpdate: @escaping (OuroMDUpdatePlan, @escaping @Sendable (String) async -> Void) async throws -> OuroMDUpdateInstaller.Staged = { plan, progress in
            try await Task.detached(priority: .utility) {
                try await OuroMDUpdateInstaller().stage(plan: plan, progress: progress)
            }.value
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

    @discardableResult
    func checkForReleaseUpdate() async -> ReleaseUpdateSnapshot {
        if let existing = inFlightCheck {
            let snapshot = await existing.task.value
            if inFlightCheck == nil || inFlightCheck === existing {
                releaseSnapshot = snapshot
            }
            return snapshot
        }
        isChecking = true
        let check = InFlightCheck(task: Task { @MainActor in
            await checker()
        })
        inFlightCheck = check
        let snapshot = await check.task.value
        if inFlightCheck === check {
            releaseSnapshot = snapshot
            inFlightCheck = nil
            isChecking = false
        }
        return snapshot
    }

    func checkForUpdatesAndPromptInstall() async {
        let snapshot = await checkForReleaseUpdate()
        discardStagedUpdateIfMismatched(with: snapshot)
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
        if let snapshot = releaseSnapshot,
           snapshot.status == .updateAvailable,
           snapshot.hasInstallableAssets,
           let version = snapshot.latestVersion {
            updatePrompt = .installable(version: version)
        } else if let version = stagedUpdateVersion {
            updatePrompt = .installable(version: version)
        }
    }

    private func discardStagedUpdateIfMismatched(with snapshot: ReleaseUpdateSnapshot) {
        guard let staged = pendingStagedUpdate else { return }
        guard snapshot.status == .updateAvailable,
              snapshot.hasInstallableAssets,
              let version = snapshot.latestVersion else {
            clearPendingStagedUpdate()
            return
        }
        if staged.version != version {
            clearPendingStagedUpdate()
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
        let snapshot = await checkForReleaseUpdate()
        guard autoUpdateEnabled,
              snapshot.status == .updateAvailable,
              snapshot.hasInstallableAssets else {
            return
        }
        await stagePendingUpdate(from: snapshot)
    }

    func installReleaseUpdate(destinationBundle: URL = Bundle.main.bundleURL) async {
        guard !isInstalling else { return }
        guard let snapshot = releaseSnapshot else {
            setInstallFailure("Check for an update first.")
            return
        }
        let plan: OuroMDUpdatePlan
        switch OuroMDUpdatePlanner.plan(from: snapshot) {
        case let .success(value):
            plan = value
        case let .failure(error):
            setInstallFailure(error.errorDescription ?? error.localizedDescription)
            return
        }
        if let staged = pendingStagedUpdate, staged.version == plan.version {
            applyStagedUpdateManually(staged, destinationBundle: destinationBundle)
            return
        } else {
            clearPendingStagedUpdate()
        }

        isInstalling = true
        installError = nil
        updatePrompt = nil
        installStatus = "Starting..."
        do {
            let staged = try await stageUpdate(plan) { status in
                await MainActor.run { self.installStatus = status }
            }
            applyStagedUpdateManually(staged, destinationBundle: destinationBundle)
        } catch {
            setInstallFailure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
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
        guard case let .success(plan) = OuroMDUpdatePlanner.plan(from: snapshot) else { return }
        if let staged = pendingStagedUpdate, staged.version == plan.version { return }
        clearPendingStagedUpdate()
        do {
            let staged = try await stageUpdate(plan) { _ in }
            pendingStagedUpdate = staged
            stagedUpdateVersion = staged.version
        } catch {
            // Background update staging is quiet; manual check/install reports errors.
        }
    }

    private func applyStagedUpdateManually(
        _ staged: OuroMDUpdateInstaller.Staged,
        destinationBundle: URL
    ) {
        isInstalling = true
        installError = nil
        updatePrompt = nil
        clearPendingStagedUpdate()
        installStatus = "Installing \(staged.version) and relaunching..."
        isApplyingManualUpdate = true
        applyAndRelaunch(staged, destinationBundle)
        terminate()
    }

    private func clearPendingStagedUpdate() {
        pendingStagedUpdate = nil
        stagedUpdateVersion = nil
    }

    private func setInstallFailure(_ detail: String) {
        installError = detail
        installStatus = nil
        isInstalling = false
        updatePrompt = .failed(detail: detail)
    }
}
