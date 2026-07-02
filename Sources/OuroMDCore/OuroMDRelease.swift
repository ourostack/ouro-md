import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.74"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-01"
    public static let releaseHighlights = [
        "Release packaging now publishes a signed DMG alongside the verified updater zip.",
        "App Store builds use a dedicated sandboxed, store-owned-updates distribution channel.",
    ]
}
