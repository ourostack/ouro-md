import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.33"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-23"
    public static let releaseHighlights = [
        "Ouro MD now uses the shared shell release checker and configuration types directly instead of carrying duplicate wrapper behavior.",
        "The app keeps only its own release identity defaults while shared shell core owns request building, parsing, and failure snapshots.",
        "Release-update tests now assert the Ouro MD identity contract on top of shell-owned update logic.",
    ]
}
