import Foundation
import Markdown

/// Renders Markdown to HTML using swift-markdown's CommonMark + GFM parser.
/// Pure, GUI-free, and unit-tested — also the engine behind `--render` and
/// the HTML/PDF export fallback.
enum MarkdownRenderer {
    /// Renders Markdown source to an HTML fragment (the contents of `<article>`).
    /// When `baseDirectory` is supplied, relative local images are inlined as
    /// base64 data URIs so they render without web-view file-access permissions.
    static func renderHTMLBody(_ markdown: String, baseDirectory: URL? = nil) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor(baseDirectory: baseDirectory)
        return visitor.visit(document)
    }
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    let baseDirectory: URL?
    private let inlineImageByteCap = 12 * 1024 * 1024

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(markup)
    }

    private mutating func renderChildren(_ markup: Markup) -> String {
        var out = ""
        for child in markup.children {
            out += visit(child)
        }
        return out
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(document)
    }

    mutating func visitText(_ text: Text) -> String {
        HTMLDocument.escape(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(renderChildren(paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let inner = renderChildren(heading)
        let id = HTMLVisitor.slug(plainText(of: heading))
        return "<h\(heading.level) id=\"\(id)\">\(inner)</h\(heading.level)>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(HTMLDocument.escape(inlineCode.code))</code>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }
        var langAttr = ""
        if let lang = codeBlock.language, !lang.isEmpty {
            langAttr = " class=\"language-\(HTMLDocument.escapeAttr(lang))\""
        }
        return "<pre><code\(langAttr)>\(HTMLDocument.escape(code))</code></pre>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(renderChildren(blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(renderChildren(unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        "<ol>\n\(renderChildren(orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        if let checkbox = listItem.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li class=\"task-list-item\"><input type=\"checkbox\" disabled\(checked)> \(renderChildren(listItem))</li>\n"
        }
        return "<li>\(renderChildren(listItem))</li>\n"
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = HTMLDocument.escapeAttr(link.destination ?? "")
        return "<a href=\"\(href)\">\(renderChildren(link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = HTMLDocument.escapeAttr(plainText(of: image))
        let src = resolveImageSource(image.source ?? "")
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { html.rawHTML }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { inlineHTML.rawHTML }

    mutating func visitTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        func styleFor(_ index: Int) -> String {
            guard index < alignments.count, let alignment = alignments[index] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }

        var html = "<table>\n<thead>\n<tr>\n"
        let headCells = table.head.children.compactMap { $0 as? Table.Cell }
        for (index, cell) in headCells.enumerated() {
            html += "<th\(styleFor(index))>\(renderChildren(cell))</th>\n"
        }
        html += "</tr>\n</thead>\n"

        let rows = table.body.children.compactMap { $0 as? Table.Row }
        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>\n"
                let cells = row.children.compactMap { $0 as? Table.Cell }
                for (index, cell) in cells.enumerated() {
                    html += "<td\(styleFor(index))>\(renderChildren(cell))</td>\n"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }
        html += "</table>\n"
        return html
    }

    // MARK: - Helpers

    private func resolveImageSource(_ source: String) -> String {
        guard !source.isEmpty else { return "" }
        if let scheme = URL(string: source)?.scheme?.lowercased(),
           ["http", "https", "data", "file"].contains(scheme) {
            return HTMLDocument.escapeAttr(source)
        }
        guard let baseDirectory else { return HTMLDocument.escapeAttr(source) }
        let fileURL = baseDirectory.appendingPathComponent(source).standardizedFileURL
        guard let data = try? Data(contentsOf: fileURL),
              data.count <= inlineImageByteCap,
              let mime = HTMLVisitor.mimeType(forExtension: fileURL.pathExtension) else {
            return HTMLDocument.escapeAttr(source)
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "heic": return "image/heic"
        default: return nil
        }
    }

    static func slug(_ text: String) -> String {
        var out = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if ch == " " || ch == "-" || ch == "_" {
                out.append("-")
            }
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Recursively collects the plain-text content of a Markdown node.
private func plainText(of markup: Markup) -> String {
    if let text = markup as? Text { return text.string }
    if let code = markup as? InlineCode { return code.code }
    if markup is LineBreak || markup is SoftBreak { return " " }
    return markup.children.map { plainText(of: $0) }.joined()
}
