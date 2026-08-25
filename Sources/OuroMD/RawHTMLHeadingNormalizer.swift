import Foundation
import Markdown
import OuroMDCore

enum RawHTMLHeadingNormalizer {
    private struct Heading {
        let openingRange: Range<Int>
        let contentStart: Int
        var contentEnd: Int?
    }

    private struct ForeignScope {
        let tagName: String
        let namespace: String
        let integratesHTML: Bool
    }

    private struct ScanResult {
        var headings: [Heading] = []
        var nonHeadingIDs: Set<String> = []
    }

    private struct Attribute {
        let name: String
        let nameEnd: Int
        let valueRange: Range<Int>?
    }

    static func nonHeadingIDs(in html: String) -> Set<String> {
        scan(Array(html.utf8)).nonHeadingIDs
    }

    static func normalize(_ html: String, slugger: inout HeadingAnchorSlugger) -> String {
        let bytes = Array(html.utf8)
        let headings = scan(bytes).headings
        guard !headings.isEmpty else { return html }

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + headings.count * 16)
        var cursor = 0
        for heading in headings {
            guard heading.openingRange.lowerBound >= cursor else { continue }
            output.append(contentsOf: bytes[cursor..<heading.openingRange.lowerBound])
            let contentEnd = max(heading.contentStart, heading.contentEnd ?? bytes.count)
            let text = semanticText(in: bytes, range: heading.contentStart..<min(contentEnd, bytes.count))
            let id = slugger.slug(text)
            output.append(contentsOf: replacingID(
                in: Array(bytes[heading.openingRange]),
                with: id
            ))
            cursor = heading.openingRange.upperBound
        }
        output.append(contentsOf: bytes[cursor...])
        return String(decoding: output, as: UTF8.self)
    }

    private static func scan(_ bytes: [UInt8]) -> ScanResult {
        var result = ScanResult()
        var openHeadings: [Int] = []
        var rawText = ""
        var templateDepth = 0
        var foreignScopes: [ForeignScope] = []
        var search = 0

        func inHTMLNamespace() -> Bool {
            foreignScopes.isEmpty ||
                foreignScopes.last?.namespace == "html" ||
                foreignScopes.last?.integratesHTML == true
        }

        func foreignNamespace() -> String {
            foreignScopes.last?.namespace ?? ""
        }

        func closeForeignScope(_ tagName: String) {
            guard let index = foreignScopes.lastIndex(where: { $0.tagName == tagName }) else { return }
            foreignScopes.removeSubrange(index...)
        }

        while search < bytes.count {
            if !rawText.isEmpty {
                guard let close = findClosingTag(rawText, in: bytes, from: search),
                      let end = openingTagEnd(in: bytes, from: close)
                else {
                    break
                }
                closeForeignScope(rawText)
                search = end + 1
                rawText = ""
                continue
            }

            guard let start = bytes[search...].firstIndex(of: ascii("<")) else { break }
            if hasPrefix(bytes, at: start, text: "<!--") {
                guard let end = find(bytes, text: "-->", from: start + 4) else { break }
                search = end + 3
                continue
            }
            if hasPrefix(bytes, at: start, text: "<![CDATA[") {
                guard let end = find(bytes, text: "]]>", from: start + 9) else { break }
                search = end + 3
                continue
            }
            guard start + 1 < bytes.count else { break }
            if bytes[start + 1] == ascii("!") || bytes[start + 1] == ascii("?") {
                guard let end = openingTagEnd(in: bytes, from: start) else { break }
                search = end + 1
                continue
            }

            let closing = bytes[start + 1] == ascii("/")
            let nameStart = start + (closing ? 2 : 1)
            let nameEnd = tagNameEnd(in: bytes, from: nameStart)
            guard nameEnd > nameStart,
                  let end = openingTagEnd(in: bytes, from: start)
            else {
                search = start + 1
                continue
            }
            let tagName = asciiLowercased(bytes[nameStart..<nameEnd])

            if closing {
                if isHeadingName(tagName), !openHeadings.isEmpty, !inHTMLNamespace() {
                    while foreignScopes.last?.integratesHTML == false {
                        foreignScopes.removeLast()
                    }
                }
                if inHTMLNamespace(), templateDepth == 0, isHeadingName(tagName),
                   let openIndex = openHeadings.last,
                   result.headings[openIndex].contentEnd == nil {
                    result.headings[openIndex].contentEnd = start
                    openHeadings.removeLast()
                }
                if tagName == "template", inHTMLNamespace(), templateDepth > 0 {
                    templateDepth -= 1
                }
                closeForeignScope(tagName)
                search = end + 1
                continue
            }

            let tag = Array(bytes[start...end])
            let fontBreakout = !inHTMLNamespace() && tagName == "font" &&
                attributes(in: tag).contains {
                    $0.name == "color" || $0.name == "face" || $0.name == "size"
                }
            if !inHTMLNamespace(), foreignBreakoutTagNames.contains(tagName) || fontBreakout {
                while foreignScopes.last?.integratesHTML == false {
                    foreignScopes.removeLast()
                }
            }
            let integrationParent = foreignScopes.last
            let mathMLTextException = integrationParent?.integratesHTML == true &&
                integrationParent?.namespace == "math" &&
                mathMLTextIntegrationPoints.contains(integrationParent?.tagName ?? "") &&
                mathMLTextExceptions.contains(tagName)
            let htmlNamespace = inHTMLNamespace() && !mathMLTextException
            let activeForeignNamespace = foreignNamespace()
            let insideTemplate = templateDepth > 0
            let selfClosing = syntacticallySelfClosing(tag)
            let htmlHeading = htmlNamespace && !insideTemplate && isHeadingName(tagName)

            if !insideTemplate, let id = attributeValue(named: "id", in: tag), !id.isEmpty,
               !htmlHeading {
                result.nonHeadingIDs.insert(id)
            }
            if htmlHeading {
                for index in openHeadings where result.headings[index].contentEnd == nil {
                    result.headings[index].contentEnd = start
                }
                openHeadings.removeAll()
                result.headings.append(Heading(
                    openingRange: start..<(end + 1),
                    contentStart: end + 1,
                    contentEnd: nil
                ))
                openHeadings.append(result.headings.count - 1)
            }

            if htmlNamespace, tagName == "template" {
                templateDepth += 1
            }
            if htmlNamespace, rawTextTagNames.contains(tagName) {
                rawText = tagName
            } else if !htmlNamespace, !selfClosing,
                      tagName == "script" || tagName == "style" {
                rawText = tagName
            }
            if htmlNamespace, tagName == "svg" || tagName == "math" {
                if !selfClosing {
                    foreignScopes.append(ForeignScope(
                        tagName: tagName,
                        namespace: tagName,
                        integratesHTML: false
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "svg",
                      svgHTMLIntegrationPoints.contains(tagName) {
                if !selfClosing {
                    foreignScopes.append(ForeignScope(
                        tagName: tagName,
                        namespace: "svg",
                        integratesHTML: true
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "math",
                      mathMLTextIntegrationPoints.contains(tagName) {
                if !selfClosing {
                    foreignScopes.append(ForeignScope(
                        tagName: tagName,
                        namespace: "math",
                        integratesHTML: true
                    ))
                }
            } else if mathMLTextException {
                if !selfClosing {
                    foreignScopes.append(ForeignScope(
                        tagName: tagName,
                        namespace: "math",
                        integratesHTML: false
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "math",
                      tagName == "annotation-xml",
                      let encoding = attributeValue(named: "encoding", in: tag)?.lowercased(),
                      encoding == "text/html" || encoding == "application/xhtml+xml" {
                if !selfClosing {
                    foreignScopes.append(ForeignScope(
                        tagName: tagName,
                        namespace: "math",
                        integratesHTML: true
                    ))
                }
            } else if htmlNamespace, !foreignScopes.isEmpty, !htmlVoidTagNames.contains(tagName) {
                // HTML self-closing syntax is ignored for non-void elements.
                foreignScopes.append(ForeignScope(
                    tagName: tagName,
                    namespace: "html",
                    integratesHTML: false
                ))
            }
            search = end + 1
        }

        for index in openHeadings where result.headings[index].contentEnd == nil {
            result.headings[index].contentEnd = bytes.count
        }
        return result
    }

    private static let rawTextTagNames: Set<String> = [
        "script", "style", "textarea", "title", "xmp", "iframe", "noembed", "noframes",
    ]
    private static let foreignBreakoutTagNames: Set<String> = [
        "b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt",
        "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img",
        "li", "listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small",
        "span", "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var",
    ]
    private static let svgHTMLIntegrationPoints: Set<String> = ["desc", "foreignobject", "title"]
    private static let mathMLTextIntegrationPoints: Set<String> = ["mi", "mo", "mn", "ms", "mtext"]
    private static let mathMLTextExceptions: Set<String> = ["malignmark", "mglyph"]
    private static let htmlVoidTagNames: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
        "param", "source", "track", "wbr",
    ]

    private static func semanticText(in bytes: [UInt8], range: Range<Int>) -> String {
        guard !range.isEmpty else { return "" }
        var output = ""
        var cursor = range.lowerBound
        var textStart = cursor
        var scopes: [ForeignScope] = []

        func appendDecoded(_ source: Range<Int>) {
            guard !source.isEmpty else { return }
            output += decodeHTMLEntities(String(decoding: bytes[source], as: UTF8.self))
        }

        func inHTMLNamespace() -> Bool {
            scopes.isEmpty || scopes.last?.namespace == "html" || scopes.last?.integratesHTML == true
        }

        func closeScope(_ tagName: String) {
            guard let index = scopes.lastIndex(where: { $0.tagName == tagName }) else { return }
            scopes.removeSubrange(index...)
        }

        while cursor < range.upperBound {
            guard bytes[cursor] == ascii("<") else {
                cursor += 1
                continue
            }
            appendDecoded(textStart..<cursor)
            if hasPrefix(bytes, at: cursor, text: "<!--"),
               let end = find(bytes, text: "-->", from: cursor + 4),
               end < range.upperBound {
                cursor = end + 3
                textStart = cursor
                continue
            }
            if hasPrefix(bytes, at: cursor, text: "<![CDATA["),
               let end = find(bytes, text: "]]>", from: cursor + 9),
               end < range.upperBound {
                output += String(decoding: bytes[(cursor + 9)..<end], as: UTF8.self)
                cursor = end + 3
                textStart = cursor
                continue
            }
            guard let end = openingTagEnd(in: bytes, from: cursor), end < range.upperBound else {
                output += "<"
                cursor += 1
                textStart = cursor
                continue
            }
            let closing = cursor + 1 < bytes.count && bytes[cursor + 1] == ascii("/")
            let nameStart = cursor + (closing ? 2 : 1)
            let nameEnd = tagNameEnd(in: bytes, from: nameStart)
            let name = asciiLowercased(bytes[nameStart..<nameEnd])
            let tag = Array(bytes[cursor...end])
            if closing {
                closeScope(name)
                cursor = end + 1
                textStart = cursor
                continue
            }

            let fontBreakout = !inHTMLNamespace() && name == "font" &&
                attributes(in: tag).contains {
                    $0.name == "color" || $0.name == "face" || $0.name == "size"
                }
            if !inHTMLNamespace(), foreignBreakoutTagNames.contains(name) || fontBreakout {
                while scopes.last?.integratesHTML == false {
                    scopes.removeLast()
                }
            }
            let integrationParent = scopes.last
            let mathMLTextException = integrationParent?.integratesHTML == true &&
                integrationParent?.namespace == "math" &&
                mathMLTextIntegrationPoints.contains(integrationParent?.tagName ?? "") &&
                mathMLTextExceptions.contains(name)
            let htmlNamespace = inHTMLNamespace() && !mathMLTextException
            let activeForeignNamespace = scopes.last?.namespace ?? ""
            let selfClosing = syntacticallySelfClosing(tag)

            if htmlNamespace, name == "br" {
                output += " "
            } else if htmlNamespace, name == "img",
                      let alt = attributeValue(named: "alt", in: tag) {
                output += alt
            } else if htmlNamespace, name == "template",
                      let close = findClosingTag(name, in: bytes, from: end + 1),
                      let closeEnd = openingTagEnd(in: bytes, from: close),
                      closeEnd < range.upperBound {
                cursor = closeEnd + 1
                textStart = cursor
                continue
            }

            let rawText = (htmlNamespace && rawTextTagNames.contains(name)) ||
                (!htmlNamespace && !selfClosing && (name == "script" || name == "style"))
            if rawText {
                if let close = findClosingTag(name, in: bytes, from: end + 1),
                   close < range.upperBound,
                   let closeEnd = openingTagEnd(in: bytes, from: close),
                   closeEnd < range.upperBound {
                    let raw = String(decoding: bytes[(end + 1)..<close], as: UTF8.self)
                    if htmlNamespace && (name == "textarea" || name == "title") {
                        output += decodeHTMLEntities(raw)
                    } else {
                        output += raw
                    }
                    cursor = closeEnd + 1
                    textStart = cursor
                    continue
                }
                output += String(decoding: bytes[(end + 1)..<range.upperBound], as: UTF8.self)
                cursor = range.upperBound
                textStart = cursor
                break
            }

            if htmlNamespace, name == "svg" || name == "math" {
                if !selfClosing {
                    scopes.append(ForeignScope(
                        tagName: name,
                        namespace: name,
                        integratesHTML: false
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "svg",
                      svgHTMLIntegrationPoints.contains(name) {
                if !selfClosing {
                    scopes.append(ForeignScope(
                        tagName: name,
                        namespace: "svg",
                        integratesHTML: true
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "math",
                      mathMLTextIntegrationPoints.contains(name) {
                if !selfClosing {
                    scopes.append(ForeignScope(
                        tagName: name,
                        namespace: "math",
                        integratesHTML: true
                    ))
                }
            } else if mathMLTextException {
                if !selfClosing {
                    scopes.append(ForeignScope(
                        tagName: name,
                        namespace: "math",
                        integratesHTML: false
                    ))
                }
            } else if !htmlNamespace, activeForeignNamespace == "math",
                      name == "annotation-xml",
                      let encoding = attributeValue(named: "encoding", in: tag)?.lowercased(),
                      encoding == "text/html" || encoding == "application/xhtml+xml" {
                if !selfClosing {
                    scopes.append(ForeignScope(
                        tagName: name,
                        namespace: "math",
                        integratesHTML: true
                    ))
                }
            } else if htmlNamespace, !scopes.isEmpty, !htmlVoidTagNames.contains(name) {
                scopes.append(ForeignScope(
                    tagName: name,
                    namespace: "html",
                    integratesHTML: false
                ))
            }
            cursor = end + 1
            textStart = cursor
        }
        appendDecoded(textStart..<range.upperBound)
        return output
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String, inAttribute: Bool = false) -> String {
        guard text.contains("&") else { return text }
        var safeMarkdown = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&",
               let reference = characterReference(in: text, at: index, inAttribute: inAttribute) {
                safeMarkdown += reference.markdown
                index = reference.end
                continue
            }
            for scalar in text[index].unicodeScalars {
                safeMarkdown += "&#x\(String(scalar.value, radix: 16));"
            }
            index = text.index(after: index)
        }
        let document = Document(parsing: safeMarkdown)
        return decodedText(of: document)
    }

    private static func characterReference(
        in text: String,
        at ampersand: String.Index,
        inAttribute: Bool
    ) -> (markdown: String, end: String.Index)? {
        var cursor = text.index(after: ampersand)
        guard cursor < text.endIndex else { return nil }

        if text[cursor] == "#" {
            cursor = text.index(after: cursor)
            var hexadecimal = false
            if cursor < text.endIndex, text[cursor] == "x" || text[cursor] == "X" {
                hexadecimal = true
                cursor = text.index(after: cursor)
            }
            let digitsStart = cursor
            var value = 0
            while cursor < text.endIndex {
                let digit = hexadecimal
                    ? asciiHexDigitValue(text[cursor])
                    : asciiDigitValue(text[cursor])
                guard let digit else { break }
                if value <= 0x10FFFF {
                    value = min(0x110000, value * (hexadecimal ? 16 : 10) + digit)
                }
                cursor = text.index(after: cursor)
            }
            guard cursor > digitsStart else { return nil }
            let sourceEnd = cursor < text.endIndex && text[cursor] == ";"
                ? text.index(after: cursor)
                : cursor
            let decoded = htmlNumericReference(value)
            return ("&#x\(String(decoded, radix: 16));", sourceEnd)
        }

        let nameStart = cursor
        while cursor < text.endIndex, isASCIIAlphaNumeric(text[cursor]) {
            cursor = text.index(after: cursor)
        }
        guard cursor > nameStart else { return nil }
        if cursor < text.endIndex, text[cursor] == ";" {
            let end = text.index(after: cursor)
            return (String(text[ampersand..<end]), end)
        }

        var candidateEnd = cursor
        while candidateEnd > nameStart {
            let name = String(text[nameStart..<candidateEnd])
            if legacySemicolonlessEntities.contains(name) {
                if inAttribute, candidateEnd < text.endIndex {
                    let next = text[candidateEnd]
                    if isASCIIAlphaNumeric(next) || next == "=" { return nil }
                }
                return ("&\(name);", candidateEnd)
            }
            candidateEnd = text.index(before: candidateEnd)
        }
        return nil
    }

    private static func asciiDigitValue(_ character: Character) -> Int? {
        guard let value = character.asciiValue else { return nil }
        guard value >= ascii("0") && value <= ascii("9") else { return nil }
        return Int(value - ascii("0"))
    }

    private static func asciiHexDigitValue(_ character: Character) -> Int? {
        guard let value = character.asciiValue else { return nil }
        if value >= ascii("0") && value <= ascii("9") {
            return Int(value - ascii("0"))
        }
        if value >= ascii("A") && value <= ascii("F") {
            return Int(value - ascii("A")) + 10
        }
        if value >= ascii("a") && value <= ascii("f") {
            return Int(value - ascii("a")) + 10
        }
        return nil
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return (value >= ascii("A") && value <= ascii("Z")) ||
            (value >= ascii("a") && value <= ascii("z")) ||
            (value >= ascii("0") && value <= ascii("9"))
    }

    private static func htmlNumericReference(_ value: Int) -> Int {
        if value == 0 || value > 0x10FFFF || (0xD800...0xDFFF).contains(value) {
            return 0xFFFD
        }
        return htmlC1Replacements[value] ?? value
    }

    private static let htmlC1Replacements: [Int: Int] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
        0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
        0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
        0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
        0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
        0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
        0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]

    private static func decodedText(of markup: Markup) -> String {
        if let text = markup as? Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        if markup is LineBreak || markup is SoftBreak { return " " }
        return markup.children.map { decodedText(of: $0) }.joined()
    }

    private static let legacySemicolonlessEntities: Set<String> = [
        "AElig", "AMP", "Aacute", "Acirc", "Agrave", "Aring", "Atilde", "Auml", "COPY",
        "Ccedil", "ETH", "Eacute", "Ecirc", "Egrave", "Euml", "GT", "Iacute", "Icirc",
        "Igrave", "Iuml", "LT", "Ntilde", "Oacute", "Ocirc", "Ograve", "Oslash", "Otilde",
        "Ouml", "QUOT", "REG", "THORN", "Uacute", "Ucirc", "Ugrave", "Uuml", "Yacute",
        "aacute", "acirc", "acute", "aelig", "agrave", "amp", "aring", "atilde", "auml",
        "brvbar", "ccedil", "cedil", "cent", "copy", "curren", "deg", "divide", "eacute",
        "ecirc", "egrave", "eth", "euml", "frac12", "frac14", "frac34", "gt", "iacute",
        "icirc", "iexcl", "igrave", "iquest", "iuml", "laquo", "lt", "macr", "micro",
        "middot", "nbsp", "not", "ntilde", "oacute", "ocirc", "ograve", "ordf", "ordm",
        "oslash", "otilde", "ouml", "para", "plusmn", "pound", "quot", "raquo", "reg",
        "sect", "shy", "sup1", "sup2", "sup3", "szlig", "thorn", "times", "uacute",
        "ucirc", "ugrave", "uml", "uuml", "yacute", "yen", "yuml",
    ]

    private static func replacingID(in tag: [UInt8], with id: String) -> [UInt8] {
        if let attribute = attributes(in: tag).first(where: { $0.name == "id" }) {
            if let valueRange = attribute.valueRange {
                return Array(tag[..<valueRange.lowerBound]) + Array(id.utf8) + Array(tag[valueRange.upperBound...])
            }
            return Array(tag[..<attribute.nameEnd]) + Array("=\"\(id)\"".utf8) + Array(tag[attribute.nameEnd...])
        }
        var insertion = max(0, tag.count - 1)
        if insertion > 0, tag[insertion - 1] == ascii("/") {
            insertion -= 1
        }
        return Array(tag[..<insertion]) + Array(" id=\"\(id)\"".utf8) + Array(tag[insertion...])
    }

    private static func attributeValue(named name: String, in tag: [UInt8]) -> String? {
        guard let attribute = attributes(in: tag).first(where: { $0.name == name }),
              let valueRange = attribute.valueRange
        else {
            return nil
        }
        return decodeHTMLEntities(
            String(decoding: tag[valueRange], as: UTF8.self),
            inAttribute: true
        )
    }

    private static func attributes(in tag: [UInt8]) -> [Attribute] {
        guard tag.count >= 3 else { return [] }
        var index = 1
        if tag[index] == ascii("/") { index += 1 }
        index = tagNameEnd(in: tag, from: index)
        var result: [Attribute] = []

        while index < tag.count - 1 {
            while index < tag.count - 1, isASCIIWhitespace(tag[index]) { index += 1 }
            if index >= tag.count - 1 || tag[index] == ascii(">") || tag[index] == ascii("/") {
                break
            }
            let nameStart = index
            while index < tag.count - 1,
                  !isASCIIWhitespace(tag[index]),
                  tag[index] != ascii("="),
                  tag[index] != ascii("/"),
                  tag[index] != ascii(">") {
                index += 1
            }
            let nameEnd = index
            let attributeName = asciiLowercased(tag[nameStart..<nameEnd])
            while index < tag.count - 1, isASCIIWhitespace(tag[index]) { index += 1 }
            guard index < tag.count - 1, tag[index] == ascii("=") else {
                result.append(Attribute(name: attributeName, nameEnd: nameEnd, valueRange: nil))
                continue
            }
            index += 1
            while index < tag.count - 1, isASCIIWhitespace(tag[index]) { index += 1 }
            if index >= tag.count - 1 {
                result.append(Attribute(name: attributeName, nameEnd: nameEnd, valueRange: index..<index))
                break
            }
            let quote = tag[index]
            if quote == ascii("\"") || quote == ascii("'") {
                let valueStart = index + 1
                index = valueStart
                while index < tag.count - 1, tag[index] != quote { index += 1 }
                result.append(Attribute(name: attributeName, nameEnd: nameEnd, valueRange: valueStart..<index))
                if index < tag.count - 1 { index += 1 }
            } else {
                let valueStart = index
                while index < tag.count - 1,
                      !isASCIIWhitespace(tag[index]),
                      tag[index] != ascii(">") {
                    index += 1
                }
                result.append(Attribute(name: attributeName, nameEnd: nameEnd, valueRange: valueStart..<index))
            }
        }
        return result
    }

    private static func syntacticallySelfClosing(_ tag: [UInt8]) -> Bool {
        guard tag.last == ascii(">") else { return false }
        var index = tag.count - 1
        while index > 0, isASCIIWhitespace(tag[index - 1]) { index -= 1 }
        return index > 0 && tag[index - 1] == ascii("/")
    }

    private static func findClosingTag(_ name: String, in bytes: [UInt8], from start: Int) -> Int? {
        var cursor = start
        while cursor + name.utf8.count + 2 < bytes.count {
            guard let candidate = bytes[cursor...].firstIndex(of: ascii("<")) else { return nil }
            let nameStart = candidate + 2
            if candidate + 2 < bytes.count,
               bytes[candidate + 1] == ascii("/"),
               asciiLowercased(bytes[nameStart..<min(nameStart + name.utf8.count, bytes.count)]) == name {
                let boundary = nameStart + name.utf8.count
                if boundary < bytes.count,
                   isASCIIWhitespace(bytes[boundary]) || bytes[boundary] == ascii("/") || bytes[boundary] == ascii(">") {
                    return candidate
                }
            }
            cursor = candidate + 1
        }
        return nil
    }

    private static func openingTagEnd(in bytes: [UInt8], from start: Int) -> Int? {
        enum State {
            case tagName
            case beforeAttribute
            case attributeName
            case afterAttribute
            case beforeValue
            case unquotedValue
        }

        var quote: UInt8?
        var state = State.tagName
        var index = start + 1
        while index < bytes.count {
            let byte = bytes[index]
            if let activeQuote = quote {
                if byte == activeQuote { quote = nil }
            } else if byte == ascii(">") {
                return index
            } else {
                switch state {
                case .tagName:
                    if isASCIIWhitespace(byte) { state = .beforeAttribute }
                case .beforeAttribute:
                    if isASCIIWhitespace(byte) || byte == ascii("/") {
                        break
                    }
                    state = .attributeName
                case .attributeName:
                    if byte == ascii("=") {
                        state = .beforeValue
                    } else if isASCIIWhitespace(byte) {
                        state = .afterAttribute
                    }
                case .afterAttribute:
                    if byte == ascii("=") {
                        state = .beforeValue
                    } else if !isASCIIWhitespace(byte) {
                        state = byte == ascii("/") ? .beforeAttribute : .attributeName
                    }
                case .beforeValue:
                    if isASCIIWhitespace(byte) {
                        break
                    }
                    if byte == ascii("\"") || byte == ascii("'") {
                        quote = byte
                        state = .beforeAttribute
                    } else {
                        state = .unquotedValue
                    }
                case .unquotedValue:
                    if isASCIIWhitespace(byte) { state = .beforeAttribute }
                }
            }
            index += 1
        }
        return nil
    }

    private static func tagNameEnd(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, isTagNameByte(bytes[index]) { index += 1 }
        return index
    }

    private static func isTagNameByte(_ byte: UInt8) -> Bool {
        (byte >= ascii("A") && byte <= ascii("Z")) ||
            (byte >= ascii("a") && byte <= ascii("z")) ||
            (byte >= ascii("0") && byte <= ascii("9")) ||
            byte == ascii(":") || byte == ascii("-")
    }

    private static func isHeadingName(_ name: String) -> Bool {
        name.count == 2 && name.first == "h" && ("1"..."6").contains(String(name.last ?? "0"))
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == ascii(" ") || byte == ascii("\t") || byte == ascii("\n") ||
            byte == ascii("\r") || byte == 0x0C
    }

    private static func asciiLowercased<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        String(decoding: bytes.map { byte in
            byte >= ascii("A") && byte <= ascii("Z") ? byte + 32 : byte
        }, as: UTF8.self)
    }

    private static func hasPrefix(_ bytes: [UInt8], at index: Int, text: String) -> Bool {
        let expected = Array(text.utf8)
        guard index + expected.count <= bytes.count else { return false }
        return bytes[index..<(index + expected.count)].elementsEqual(expected)
    }

    private static func find(_ bytes: [UInt8], text: String, from start: Int) -> Int? {
        let needle = Array(text.utf8)
        guard !needle.isEmpty, start < bytes.count else { return nil }
        var index = start
        while index + needle.count <= bytes.count {
            if bytes[index..<(index + needle.count)].elementsEqual(needle) { return index }
            index += 1
        }
        return nil
    }

    private static func ascii(_ character: Character) -> UInt8 {
        character.asciiValue!
    }
}
