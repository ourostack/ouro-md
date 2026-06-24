import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.36"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-24"
    public static let releaseHighlights = [
        "Tables now align flush with the body text's left edge (GitHub-style) instead of being centered or shoved into the page margin.",
        "Narrow tables shrink to their content instead of being padded to a fixed width, while long-text and code-bearing cells keep a readable minimum so wide tables never collapse into ribbons.",
        "The table layout probe now verifies left-edge alignment and ribbon-free code cells across viewport widths.",
    ]
}
