import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.77"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-02"
    public static let releaseHighlights = [
        "The Mac App Store lane now has a first-class readiness check for signing identities and App Store Connect auth.",
        "App Store packaging accepts explicit App Store Connect API key files for validation and upload.",
        "Release policy now guards the App Store packaging contract alongside the direct-download release lane.",
    ]
}
