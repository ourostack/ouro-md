import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.61"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-29"
    public static let releaseHighlights = [
        "Keep release freshness checks working when the GitHub CLI keyring is unhealthy by falling back to GitHub's release API.",
    ]
}
