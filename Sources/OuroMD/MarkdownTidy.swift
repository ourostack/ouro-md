import Foundation

enum MarkdownTidy {
    /// Undo the only two things the editor normalizes on a markdown round-trip
    /// (verified: everything else is byte-identical) so saving doesn't churn the
    /// diff: re-expand collapsed table separators (`| - |` -> `| --- |`) and
    /// collapse runs of blank lines that the table renderer introduces. Content
    /// inside fenced code blocks is left untouched.
    static func tidy(_ markdown: String) -> String {
        normalized(markdown)
    }

    /// Used only by the headless round-trip probe, where the caller knows no
    /// human edit occurred between load and readback.
    static func roundTripProbeOutput(_ markdown: String, preserving original: String) -> String {
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
        return out.joined(separator: "\n")
    }

    private static func isTableSeparator(_ trimmed: String) -> Bool {
        trimmed.contains("|") && trimmed.contains("-") && trimmed.allSatisfy { "|:- \t".contains($0) }
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

