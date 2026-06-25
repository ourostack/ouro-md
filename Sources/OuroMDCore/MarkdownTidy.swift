import Foundation

public enum MarkdownTidy {
    /// Undo the only two things the editor normalizes on a markdown round-trip
    /// (verified: everything else is byte-identical) so saving doesn't churn the
    /// diff: re-expand collapsed table separators (`| - |` -> `| --- |`) and
    /// collapse runs of blank lines that the table renderer introduces. Content
    /// inside fenced code blocks is left untouched.
    public static func tidy(_ markdown: String) -> String {
        normalized(markdown)
    }

    /// Used only by the headless round-trip probe, where the caller knows no
    /// human edit occurred between load and readback.
    public static func roundTripProbeOutput(_ markdown: String, preserving original: String) -> String {
        let tidied = normalized(markdown)
        if normalized(original) == tidied {
            return original
        }
        return tidied
    }

    private static func normalized(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var out: [String] = []
        var inFence = false
        var prevBlank = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                out.append(line)
                prevBlank = false
                continue
            }
            if inFence {
                out.append(line)
                continue
            }
            if trimmed.isEmpty {
                if prevBlank { continue }
                prevBlank = true
                out.append(line)
                continue
            }
            prevBlank = false
            out.append(isTableSeparator(trimmed) ? expandTableSeparator(line) : line)
        }
        return restoreFrontMatterBlankLine(out).joined(separator: "\n")
    }

    /// YAML front matter (`---` … `---` at the very top) is conventionally
    /// followed by a blank line before the body. Vditor drops that blank line on
    /// save; restore it so agent-authored docs (task cards, etc.) round-trip
    /// without a churned diff. Only fires for genuine leading front matter.
    private static func restoreFrontMatterBlankLine(_ lines: [String]) -> [String] {
        guard lines.first == "---" else { return lines }
        // Find the closing fence (first `---` after line 0).
        guard let close = lines.dropFirst().firstIndex(of: "---") else { return lines }
        let afterClose = close + 1
        // Already at end, or already followed by a blank line — nothing to do.
        guard afterClose < lines.count else { return lines }
        if lines[afterClose].trimmingCharacters(in: .whitespaces).isEmpty { return lines }
        var result = lines
        result.insert("", at: afterClose)
        return result
    }

    /// A GFM table delimiter row in the leading/trailing-pipe form the editor
    /// emits (`| --- | :---: | ---: |`). Requires the line to be bounded by pipes
    /// and every cell to be a delimiter cell — optional leading colon, one or more
    /// dashes, optional trailing colon — so non-table lines that merely use the
    /// same characters (a bullet `- |`, an alignment-only `| : | : |`) are NOT
    /// mistaken for separators and rewritten.
    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let cells = trimmed.dropFirst().dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return !cells.isEmpty && cells.allSatisfy(isDelimiterCell)
    }

    private static func isDelimiterCell(_ cell: String) -> Bool {
        var body = Substring(cell)
        if body.first == ":" { body = body.dropFirst() }
        if body.last == ":" { body = body.dropLast() }
        return !body.isEmpty && body.allSatisfy { $0 == "-" }
    }

    private static func expandTableSeparator(_ line: String) -> String {
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var cells = line.trimmingCharacters(in: .whitespaces)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        let cols = cells.map { cell -> String in
            (cell.hasPrefix(":") ? ":" : "") + "---" + (cell.hasSuffix(":") ? ":" : "")
        }
        return leading + "| " + cols.joined(separator: " | ") + " |"
    }
}

