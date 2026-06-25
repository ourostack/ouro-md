import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.42"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-25"
    public static let releaseHighlights = [
        "Search result reveal is more reliable in throttled WebKit surfaces, so sidebar matches still select the intended rendered text.",
        "Native validation now reports actionable undo/search reveal diagnostics instead of timing out silently.",
    ]
}
