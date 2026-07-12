import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.82"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-07-12"
    public static let positioningSubtitle = "Local Markdown workspace for Mac files."
    public static let releaseHighlights = [
        "External edits now live-reload reliably in place — when an agent or another editor rewrites the open file, Ouro MD reflects it without a relaunch, even across rapid successive saves, and your scroll position is kept.",
        "File status moved from a footer bar to a quiet glyph in the title bar, keeping the editor surface distraction-free; click it for reveal-in-Finder, copy-path, and copy-git-diff actions. Focus Mode hides it entirely.",
        "Click the filename in the title bar to open another document (with the usual unsaved-changes prompt); Rename stays on the File menu.",
    ]
}
