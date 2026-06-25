import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.37"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-24"
    public static let releaseHighlights = [
        "Maintenance release: no user-facing changes.",
        "Internal: the build's version is now single-sourced from the app's release metadata, so the packaged version can't drift and a release bump can't be applied only partway.",
    ]
}
