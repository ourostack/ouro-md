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
        let footnoted = FootnotePreprocessor.process(markdown)
        let document = Document(parsing: footnoted.markdown)
        var visitor = HTMLVisitor(baseDirectory: baseDirectory)
        var html = visitor.visit(document)
        if !footnoted.footnotes.isEmpty {
            html += renderFootnotes(footnoted.footnotes, baseDirectory: baseDirectory)
        }
        return html
    }

    private static func renderFootnotes(_ footnotes: [RenderedFootnote], baseDirectory: URL?) -> String {
        var html = "<section class=\"footnotes\">\n<hr>\n<ol>\n"
        for footnote in footnotes {
            let document = Document(parsing: footnote.markdown)
            var visitor = HTMLVisitor(baseDirectory: baseDirectory)
            let body = visitor.visit(document).trimmingCharacters(in: .whitespacesAndNewlines)
            html += "<li id=\"fn-\(HTMLDocument.escapeAttr(footnote.id))\">\(body) "
            html += "<a href=\"#fnref-\(HTMLDocument.escapeAttr(footnote.id))\" class=\"footnote-backref\">&#8617;</a></li>\n"
        }
        html += "</ol>\n</section>\n"
        return html
    }
}

private struct RenderedFootnote: Equatable {
    var label: String
    var id: String
    var markdown: String
}

private enum FootnotePreprocessor {
    private struct Definition {
        var label: String
        var markdown: String
    }

    private struct Fence {
        var marker: Character
        var length: Int
    }

    struct Output {
        var markdown: String
        var footnotes: [RenderedFootnote]
    }

    static func process(_ markdown: String) -> Output {
        let extracted = extractDefinitions(markdown)
        guard !extracted.definitions.isEmpty else {
            return Output(markdown: markdown, footnotes: [])
        }

        var idsByLabel: [String: String] = [:]
        var numbersByLabel: [String: Int] = [:]
        for (offset, definition) in extracted.definitions.enumerated() {
            idsByLabel[definition.label] = footnoteID(label: definition.label, index: offset + 1)
            numbersByLabel[definition.label] = offset + 1
        }
        let referenced = replaceReferences(
            in: extracted.markdownWithoutDefinitions,
            idsByLabel: idsByLabel,
            numbersByLabel: numbersByLabel
        )
        let footnotes = extracted.definitions.map {
            RenderedFootnote(label: $0.label, id: idsByLabel[$0.label] ?? $0.label, markdown: $0.markdown)
        }
        return Output(markdown: referenced, footnotes: footnotes)
    }

    private static func extractDefinitions(_ markdown: String) -> (markdownWithoutDefinitions: String, definitions: [Definition]) {
        let lines = markdown.components(separatedBy: "\n")
        var bodyLines: [String] = []
        var definitions: [Definition] = []
        var seenLabels: Set<String> = []
        var activeDefinitionIndex: Int?
        var activeFence: Fence?

        for line in lines {
            if let fence = parseFence(line) {
                activeDefinitionIndex = nil
                if let existing = activeFence {
                    if fence.marker == existing.marker && fence.length >= existing.length {
                        activeFence = nil
                    }
                } else {
                    activeFence = fence
                }
                bodyLines.append(line)
                continue
            }
            if activeFence != nil {
                bodyLines.append(line)
                continue
            }
            if let definition = parseDefinition(line) {
                if seenLabels.insert(definition.label).inserted {
                    definitions.append(definition)
                    activeDefinitionIndex = definitions.count - 1
                } else {
                    activeDefinitionIndex = nil
                }
                continue
            }
            if let index = activeDefinitionIndex, line.trimmingCharacters(in: .whitespaces).isEmpty {
                definitions[index].markdown += "\n"
                continue
            }
            if let index = activeDefinitionIndex, let continuation = continuationContent(line) {
                definitions[index].markdown += "\n" + continuation
                continue
            }
            activeDefinitionIndex = nil
            bodyLines.append(line)
        }

        return (bodyLines.joined(separator: "\n"), definitions)
    }

    private static func parseDefinition(_ line: String) -> Definition? {
        guard indentationWidth(line) <= 3 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[^"),
              let close = trimmed.range(of: "]:")
        else {
            return nil
        }
        let labelStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let label = String(trimmed[labelStart..<close.lowerBound])
        guard !label.isEmpty else { return nil }
        let markdown = String(trimmed[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        return Definition(label: label, markdown: markdown)
    }

    private static func parseFence(_ line: String) -> Fence? {
        guard indentationWidth(line) <= 3 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        var length = 0
        for char in trimmed {
            if char == first {
                length += 1
            } else {
                break
            }
        }
        guard length >= 3 else { return nil }
        return Fence(marker: first, length: length)
    }

    private static func indentationWidth(_ line: String) -> Int {
        var width = 0
        for char in line {
            if char == " " {
                width += 1
            } else if char == "\t" {
                width += 4
            } else {
                break
            }
        }
        return width
    }

    private static func continuationContent(_ line: String) -> String? {
        if line.hasPrefix("    ") {
            return String(line.dropFirst(4))
        }
        if line.hasPrefix("\t") {
            return String(line.dropFirst())
        }
        return nil
    }

    private static func replaceReferences(
        in markdown: String,
        idsByLabel: [String: String],
        numbersByLabel: [String: Int]
    ) -> String {
        var output: [String] = []
        var activeFence: Fence?
        for line in markdown.components(separatedBy: "\n") {
            if let fence = parseFence(line) {
                if let existing = activeFence {
                    if fence.marker == existing.marker && fence.length >= existing.length {
                        activeFence = nil
                    }
                } else {
                    activeFence = fence
                }
                output.append(line)
                continue
            }
            output.append((activeFence != nil || indentationWidth(line) >= 4)
                ? line
                : replaceReferences(inLine: line, idsByLabel: idsByLabel, numbersByLabel: numbersByLabel))
        }
        return output.joined(separator: "\n")
    }

    private static func replaceReferences(
        inLine line: String,
        idsByLabel: [String: String],
        numbersByLabel: [String: Int]
    ) -> String {
        var out = ""
        var index = line.startIndex
        var backtickRun: Int?
        while index < line.endIndex {
            let char = line[index]
            if char == "\\" {
                out.append(char)
                index = line.index(after: index)
                if index < line.endIndex {
                    out.append(line[index])
                    index = line.index(after: index)
                }
                continue
            }
            if char == "`" {
                let run = countBackticks(in: line, at: index)
                out += String(repeating: "`", count: run)
                index = line.index(index, offsetBy: run)
                if let active = backtickRun {
                    if active == run { backtickRun = nil }
                } else {
                    backtickRun = run
                }
                continue
            }
            if backtickRun == nil, line[index...].hasPrefix("[^") {
                let labelStart = line.index(index, offsetBy: 2)
                if let close = line[labelStart...].firstIndex(of: "]") {
                    let label = String(line[labelStart..<close])
                    if let id = idsByLabel[label], let number = numbersByLabel[label] {
                        out += "<sup id=\"fnref-\(HTMLDocument.escapeAttr(id))\"><a href=\"#fn-\(HTMLDocument.escapeAttr(id))\" class=\"footnote-ref\">\(number)</a></sup>"
                    } else {
                        out += line[index...close]
                    }
                    index = line.index(after: close)
                    continue
                }
            }
            out.append(char)
            index = line.index(after: index)
        }
        return out
    }

    private static func countBackticks(in line: String, at index: String.Index) -> Int {
        var count = 0
        var cursor = index
        while cursor < line.endIndex, line[cursor] == "`" {
            count += 1
            cursor = line.index(after: cursor)
        }
        return count
    }

    private static func footnoteID(label: String, index: Int) -> String {
        let slug = HTMLVisitor.slug(label)
        return slug.isEmpty ? "footnote-\(index)" : slug
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
