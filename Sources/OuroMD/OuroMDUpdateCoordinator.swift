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
    private let telemetry: @MainActor (String, [String: OuroMDTelemetryValue]) -> Void
    private var inFlightCheck: InFlightCheck?
    private var pendingStagedUpdate: OuroMDUpdateInstaller.Staged?
    private var pendingManualUpdate: OuroMDUpdateInstaller.Staged?
    private var pendingManualDestinationBundle: URL?
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
        now: @escaping @MainActor () -> Date = Date.init,
        telemetry: @escaping @MainActor (String, [String: OuroMDTelemetryValue]) -> Void = {
            OuroMDTelemetry.shared.capture($0, properties: $1)
        }
    ) {
        self.defaults = defaults
        self.checker = checker
        self.stageUpdate = stageUpdate
        self.applyAndRelaunch = applyAndRelaunch
        self.applyOnQuit = applyOnQuit
        self.terminate = terminate
        self.now = now
        self.telemetry = telemetry
        self.autoUpdateEnabled = defaults.object(forKey: Self.autoUpdateEnabledDefaultsKey) as? Bool ?? true
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        autoUpdateEnabled = enabled
    }

    @discardableResult
    func checkForReleaseUpdate(trigger: String = "programmatic") async -> ReleaseUpdateSnapshot {
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
        trackUpdateCheck(snapshot, trigger: trigger)
        return snapshot
    }

    func checkForUpdatesAndPromptInstall() async {
        let snapshot = await checkForReleaseUpdate(trigger: "manual")
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
                if !newValue { self.dismissUpdatePrompt(reason: "binding") }
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

    func dismissUpdatePrompt(reason: String = "dismissed") {
        guard let prompt = updatePrompt else { return }
        updatePrompt = nil
        if case let .installable(version) = prompt {
            telemetry(
                "ouro_md_update_install_deferred",
                ["version": .string(version), "reason": .string(reason)]
            )
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
        let snapshot = await checkForReleaseUpdate(trigger: "auto")
        guard autoUpdateEnabled,
              snapshot.status == .updateAvailable,
              snapshot.hasInstallableAssets else {
            return
        }
        await stagePendingUpdate(from: snapshot)
    }

    func installReleaseUpdate(destinationBundle: URL = Bundle.main.bundleURL) async {
        guard !isInstalling else {
            telemetry("ouro_md_update_install_ignored", ["reason": .string("already_installing")])
            return
        }
        telemetry("ouro_md_update_install_requested", [:])
        guard let snapshot = releaseSnapshot else {
            setInstallFailure("Check for an update first.", code: "missing_prior_check")
            return
        }
        let plan: OuroMDUpdatePlan
        switch OuroMDUpdatePlanner.plan(from: snapshot) {
        case let .success(value):
            plan = value
        case let .failure(error):
            setInstallFailure(
                error.errorDescription ?? error.localizedDescription,
                code: Self.installPlanFailureCode(error)
            )
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
            setInstallFailure((error as? LocalizedError)?.errorDescription ?? error.localizedDescription, code: "stage_failed")
        }
    }

    func applyStagedUpdateOnQuitIfNeeded(destinationBundle: URL = Bundle.main.bundleURL) {
        guard autoUpdateEnabled, !isApplyingManualUpdate, let staged = pendingStagedUpdate else {
            return
        }
        pendingStagedUpdate = nil
        stagedUpdateVersion = nil
        telemetry("ouro_md_update_apply_on_quit", ["version": .string(staged.version)])
        applyOnQuit(staged, destinationBundle)
    }

    @discardableResult
    func applyPendingManualUpdateAndRelaunchIfNeeded() -> Bool {
        guard let staged = pendingManualUpdate,
              let destinationBundle = pendingManualDestinationBundle else {
            return false
        }
        pendingManualUpdate = nil
        pendingManualDestinationBundle = nil
        installStatus = "Installing \(staged.version) and relaunching..."
        telemetry("ouro_md_update_apply_and_relaunch", ["version": .string(staged.version)])
        applyAndRelaunch(staged, destinationBundle)
        return true
    }

    func cancelPendingManualInstall() {
        guard let staged = pendingManualUpdate else { return }
        pendingManualUpdate = nil
        pendingManualDestinationBundle = nil
        isApplyingManualUpdate = false
        isInstalling = false
        installStatus = nil
        try? FileManager.default.removeItem(at: staged.stagingRoot)
        telemetry("ouro_md_update_install_cancelled", ["version": .string(staged.version)])
    }

    private func stagePendingUpdate(from snapshot: ReleaseUpdateSnapshot) async {
        guard case let .success(plan) = OuroMDUpdatePlanner.plan(from: snapshot) else { return }
        if let staged = pendingStagedUpdate, staged.version == plan.version { return }
        clearPendingStagedUpdate()
        do {
            let staged = try await stageUpdate(plan) { _ in }
            pendingStagedUpdate = staged
            stagedUpdateVersion = staged.version
            telemetry("ouro_md_update_staged", ["version": .string(staged.version)])
        } catch {
            // Background update staging is quiet; manual check/install reports errors.
            telemetry("ouro_md_update_stage_failed", ["trigger": .string("auto")])
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
        pendingManualUpdate = staged
        pendingManualDestinationBundle = destinationBundle
        installStatus = "Ready to install \(staged.version) after Ouro MD quits..."
        isApplyingManualUpdate = true
        telemetry("ouro_md_update_install_scheduled", ["version": .string(staged.version)])
        terminate()
    }

    private func clearPendingStagedUpdate() {
        pendingStagedUpdate = nil
        stagedUpdateVersion = nil
    }

    private func setInstallFailure(_ detail: String, code: String = "unknown") {
        installError = detail
        installStatus = nil
        isInstalling = false
        updatePrompt = .failed(detail: detail)
        telemetry("ouro_md_update_install_failed", ["code": .string(code)])
    }

    private func trackUpdateCheck(_ snapshot: ReleaseUpdateSnapshot, trigger: String) {
        var properties: [String: OuroMDTelemetryValue] = [
            "trigger": .string(trigger),
            "status": .string(snapshot.status.rawValue),
            "current_version": .string(snapshot.currentVersion),
            "has_installable_assets": .bool(snapshot.hasInstallableAssets),
            "asset_count": .int(snapshot.assets.count),
        ]
        if let latestVersion = snapshot.latestVersion {
            properties["latest_version"] = .string(latestVersion)
        }
        telemetry("ouro_md_update_check_completed", properties)
    }

    private static func installPlanFailureCode(_ error: OuroMDUpdatePlanError) -> String {
        switch error {
        case .notAnUpdate:
            return "not_an_update"
        case .missingArchiveAsset:
            return "missing_archive_asset"
        case .missingManifestAsset:
            return "missing_manifest_asset"
        case .badAssetURL:
            return "bad_asset_url"
        }
    }
}
