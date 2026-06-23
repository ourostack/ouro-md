import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.25"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-23"
    public static let releaseHighlights = [
        "Shared shell release controls now prove that update review stays visible without exposing direct install from the shell surface.",
        "Ouro MD keeps install and relaunch actions behind its native prompt and menu flow while unsigned direct downloads remain the shipping path.",
        "The UI surface probe now covers the available-update shell controls as well as install progress and failure states.",
    ]
}
