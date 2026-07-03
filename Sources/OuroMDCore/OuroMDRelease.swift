import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.78"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-03"
    public static let releaseHighlights = [
        "App Store packaging now delegates signing, product packaging, validation, and upload steps through the shared Apple distribution kit.",
        "CI verifies the shared distribution-kit boundary so the Mac App Store lane cannot silently fall back to bespoke packaging.",
        "Release evidence records the active App Store provisioning profile, local signing identities, and the first-app-record blocker without storing secrets.",
    ]
}
