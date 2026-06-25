import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.38"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-24"
    public static let releaseHighlights = [
        "Maintenance release: no user-facing changes.",
        "Internal: the headless test harnesses no longer pop windows onto the screen or steal keyboard focus when the suite runs on a machine in use.",
    ]
}
