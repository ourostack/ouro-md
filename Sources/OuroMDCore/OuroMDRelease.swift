import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.39"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-24"
    public static let releaseHighlights = [
        "Maintenance release: no user-facing changes.",
        "Internal: release scripts now read the app version through one shared helper instead of three separate copies, so the version-extraction can't drift.",
    ]
}
