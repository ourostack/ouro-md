import Foundation

public struct HeadingAnchorSlugger {
    private var occurrences: [String: Int] = [:]

    public init() {}

    public mutating func slug(_ text: String) -> String {
        let base = Self.baseSlug(text)
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        return occurrence == 0 ? base : "\(base)-\(occurrence)"
    }

    public static func baseSlug(_ text: String) -> String {
        let normalized = text
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .precomposedStringWithCanonicalMapping
        var out = ""
        for scalar in normalized.unicodeScalars {
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                out.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "-" || scalar == "_" {
                out.append("-")
            }
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }
}
