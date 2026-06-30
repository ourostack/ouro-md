import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.65"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-30"
    public static let releaseHighlights = [
        "Refresh the shared native app shell dependency, adoption controls, and dependency policy metadata.",
        "Add shipped diagnostic harness and Vditor vendor provenance checks to keep release artifacts auditable.",
        "Declare shared-shell settings, telemetry, privacy diagnostics, and visual-validation surfaces for downstream policy checks.",
        "Declare the shared shell command manifest so keyboard shortcuts, menus, and What's New ownership stay in sync.",
    ]
}
