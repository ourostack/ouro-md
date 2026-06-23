import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.26"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-23"
    public static let releaseHighlights = [
        "The accessibility audit now verifies shared shell update surfaces from rendered UI instead of SwiftPM checkout source paths.",
        "Ouro MD's native scenario suite keeps proving shell update labels even when build artifacts move outside the repo.",
        "Release controls, About, and post-update confirmation labels are checked from the product surface without exposing direct shell install.",
    ]
}
