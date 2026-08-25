import Foundation

public struct HeadingAnchorSlugger {
    private var occurrences: [String: Int] = [:]
    private var used: Set<String> = []

    public init(reserving reserved: Set<String> = []) {
        used = reserved
    }

    public mutating func slug(_ text: String) -> String {
        let base = Self.baseSlug(text)
        var occurrence = occurrences[base, default: 0]
        var candidate = occurrence == 0 ? base : "\(base)-\(occurrence)"
        while used.contains(candidate) {
            occurrence += 1
            candidate = "\(base)-\(occurrence)"
        }
        occurrences[base] = occurrence + 1
        used.insert(candidate)
        return candidate
    }

    public static func baseSlug(_ text: String) -> String {
        let normalized = text
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .precomposedStringWithCanonicalMapping
        var out = ""
        for scalar in normalized.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                out.unicodeScalars.append(scalar)
            default:
                if scalar == " " || scalar == "-" || scalar == "_" {
                    out.append("-")
                }
            }
        }
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }
}
