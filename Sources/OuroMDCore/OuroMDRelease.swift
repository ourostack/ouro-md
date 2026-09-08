import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.86"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-09-08"
    public static let positioningSubtitle = "Local Markdown workspace for Mac files."
    public static let releaseHighlights = [
        "Open folders as a local Markdown workspace for Mac files, with Search and Outline surfaces available from first launch.",
        "Follow links between local Markdown files into separate native windows while keeping the source workspace on disk.",
        "Use File menu and Command Palette actions for file handoff, plus PDF and HTML export commands. No account is required.",
        "Prevent a file-watcher crash when saving or changing documents, while preserving live reload after atomic saves.",
    ]
}
