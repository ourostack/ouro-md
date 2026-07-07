import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.80"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-07"
    public static let releaseHighlights = [
        "Editing a Markdown table no longer eats the space before inline formatting — `see the **bold** item` stays intact instead of becoming `see the**bold** item`.",
        "CI checks the App Store icon, entitlement, telemetry, and encryption contracts before packaging.",
    ]
}
