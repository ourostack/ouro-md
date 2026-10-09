import Foundation

public enum OuroMDRelease {
    public static let appName = "Ouro MD"
    public static let bundleIdentifier = "bot.ouro.md"
    public static let repository = "ourostack/ouro-md"
    public static let version = "0.9.90"
    public static let userAgent = "OuroMD/\(version)"
    public static let releaseDate = "2026-10-08"
    public static let positioningSubtitle = "Local Markdown workspace for Mac files."
    public static let releaseHighlights = [
        "Open folders as a local Markdown workspace for Mac files, with Search and Outline surfaces available from first launch.",
        "Follow links between local Markdown files into separate native windows while keeping the source workspace on disk.",
        "Use File menu and Command Palette actions for file handoff, plus PDF and HTML export commands. No account is required.",
        "Prevent a file-watcher crash when saving or changing documents, while preserving live reload after atomic saves.",
        "Render HTML line breaks in the editor, including table cells, without changing the Markdown source.",
        "Text size now reflows the page, so the column stays centered and the side margins shrink in narrow windows.",
        "Selecting across bullets and numbered lists now draws one clean highlight, without seams around the markers.",
        "Built for macOS 27: the window adopts the current system design, with a glass toolbar and a floating status pill.",
        "Writing Tools rewrites text in place in the editor, and one undo reverts the whole rewrite.",
        "Siri, Shortcuts and Spotlight can open, read and add to your Markdown documents, including unsaved edits.",
    ]
}
