import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.24"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-22"
    public static let releaseHighlights = [
        "About and Software Update now render through the shared OuroAppShell UI layer.",
        "The Updates preference row, About window, and post-install confirmation keep Ouro MD's native labels while sharing shell primitives.",
        "The accessibility audit now follows shared shell sources so moved labels stay covered.",
    ]
}
