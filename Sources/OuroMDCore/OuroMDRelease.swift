import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.41"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-24"
    public static let releaseHighlights = [
        "Maintenance release: no user-facing changes.",
        "Internal: changes that only touch test harnesses no longer cut a user-facing release, so routine test/tooling tweaks stop churning the version.",
    ]
}
