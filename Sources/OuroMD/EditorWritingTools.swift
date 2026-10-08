import AppKit
import WebKit

/// Writing Tools in the editor. Ouro MD is where people and agents, Siri
/// included, work on the same Markdown, so the editor offers the complete
/// inline experience (rewrites land in the text with the system animation)
/// rather than WebKit's default overlay panel. The bridge keeps Vditor out of
/// the way during a session and folds the result back into Markdown after it.
enum EditorWritingTools {
    static func enableInlineEditing(on configuration: WKWebViewConfiguration) {
        guard #available(macOS 15, *) else { return }
        // `writingToolsBehavior` is declared only for deployment targets of
        // macOS 15 or later, so it is set by key while Ouro MD supports 13.
        let setter = NSSelectorFromString("setWritingToolsBehavior:")
        guard configuration.responds(to: setter) else { return }
        configuration.setValue(NSWritingToolsBehavior.complete.rawValue, forKey: "writingToolsBehavior")
    }

    static func behavior(of configuration: WKWebViewConfiguration) -> Int? {
        guard #available(macOS 15, *),
              configuration.responds(to: NSSelectorFromString("writingToolsBehavior")) else { return nil }
        return (configuration.value(forKey: "writingToolsBehavior") as? NSNumber)?.intValue
    }
}
