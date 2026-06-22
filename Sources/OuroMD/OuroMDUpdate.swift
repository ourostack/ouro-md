import Foundation
import OuroAppShellCore

typealias OuroMDUpdateManifest = AppUpdateManifest
typealias OuroMDUpdatePlan = AppUpdatePlan
typealias OuroMDUpdatePlanError = AppUpdatePlanError
typealias OuroMDAutoUpdatePolicy = AutoUpdatePolicy

enum OuroMDUpdatePlanner {
    static func plan(from snapshot: ReleaseUpdateSnapshot) -> Result<OuroMDUpdatePlan, OuroMDUpdatePlanError> {
        AppUpdatePlanner.plan(from: snapshot)
    }
}

enum OuroMDUpdateVerification {
    typealias Failure = AppUpdateVerification.Failure

    static func verify(
        manifest: OuroMDUpdateManifest,
        downloadedArchiveName: String,
        downloadedSHA256: String,
        downloadedBytes: Int,
        expectedBundleIdentifier: String,
        currentVersion: String
    ) -> Failure? {
        AppUpdateVerification.verify(
            manifest: manifest,
            downloadedArchiveName: downloadedArchiveName,
            downloadedSHA256: downloadedSHA256,
            downloadedBytes: downloadedBytes,
            expectedBundleIdentifier: expectedBundleIdentifier,
            currentVersion: currentVersion,
            compareBuilds: false
        )
    }
}
