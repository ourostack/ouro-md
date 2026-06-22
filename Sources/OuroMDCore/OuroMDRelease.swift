import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.23"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-22"
    public static let releaseHighlights = [
        "Release checks now use the shared OuroAppShellCore foundation.",
        "Software Update keeps stable-channel update behavior while sharing manifest verification primitives.",
        "About and update surfaces remain ready for the shared OuroAppShell UI migration.",
    ]
}
