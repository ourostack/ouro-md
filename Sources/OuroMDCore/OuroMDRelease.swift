import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.75"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-02"
    public static let releaseHighlights = [
        "Ouro MD now uses the canonical bot.ouro.md bundle identity for app, release, and App Store builds.",
        "App Store packaging now fails fast if a build drifts from the canonical bundle identity.",
    ]
}
