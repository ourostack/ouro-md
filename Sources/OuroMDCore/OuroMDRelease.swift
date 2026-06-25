import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "org.ourostack.ouro-md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.44"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-06-25"
    public static let releaseHighlights = [
        "Hardened undo/redo and release verification: editor undo/redo now no-ops safely on empty stacks, the native undo smoke waits for real editor readiness, and the accessibility audit accepts macOS confirmation-label variants.",
    ]
}
