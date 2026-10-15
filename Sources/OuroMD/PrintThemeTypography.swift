import Foundation

struct PrintThemeTypography {
    enum EditorMode: String {
        case ir
        case wysiwyg
    }

    enum ResourceError: LocalizedError {
        case missingFont(String)
        case missingEditorBase

        var errorDescription: String? {
            switch self {
            case .missingFont(let name): return "The bundled print font \(name) is missing. Reinstall the app to restore its theme fonts."
            case .missingEditorBase: return "The bundled editor resources are missing. Reinstall the app to restore its theme fonts."
            }
        }
    }

    let css: String
    let fontCSS: String
    let baseURL: URL?
    let editorMode: EditorMode

    init(css: String, fontCSS: String = "", baseURL: URL? = nil, editorMode: EditorMode = .ir) {
        self.css = css
        self.fontCSS = fontCSS
        self.baseURL = baseURL
        self.editorMode = editorMode
    }

    init(theme: Theme, editorMode: EditorMode = .ir) throws {
        guard let baseURL = OuroResources.web("index", "html") else { throw ResourceError.missingEditorBase }
        self.init(css: theme.editorCSS, fontCSS: try Self.bundledFontCSS.get(), baseURL: baseURL, editorMode: editorMode)
    }

    private static let bundledFontCSS: Result<String, Error> = Result {
        try [(400, "normal", ""), (400, "italic", "i"), (700, "normal", ""), (700, "italic", "i")].map { weight, style, suffix in
            let name = "open-sans-\(weight)\(suffix)"
            guard let url = OuroResources.web("fonts/\(name)", "woff2") else { throw ResourceError.missingFont(name) }
            let data = try Data(contentsOf: url)
            return "@font-face{font-family:'Open Sans';font-style:\(style);font-weight:\(weight);src:url('data:font/woff2;base64,\(data.base64EncodedString())') format('woff2');}"
        }.joined(separator: "\n")
    }
}
