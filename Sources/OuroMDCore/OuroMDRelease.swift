import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.79"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-03"
    public static let releaseHighlights = [
        "Mac App Store packaging now passes Apple validation with the required 1024px app icon representation.",
        "App Store signing carries the canonical application and team identifiers from the active provisioning profile.",
        "CI checks the App Store icon, entitlement, telemetry, and encryption contracts before packaging.",
    ]
}
