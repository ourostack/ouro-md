import AppKit
import Foundation

struct PrintPageMargins: Equatable, Sendable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    func clamped() -> Self {
        Self(
            top: Self.clamp(top, fallback: PrintLayoutSettings.default.margins.top),
            right: Self.clamp(right, fallback: PrintLayoutSettings.default.margins.right),
            bottom: Self.clamp(bottom, fallback: PrintLayoutSettings.default.margins.bottom),
            left: Self.clamp(left, fallback: PrintLayoutSettings.default.margins.left)
        )
    }

    static func clamp(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(144, max(18, value))
    }
}

struct PrintLayoutSettings: Equatable, Sendable {
    enum CitationMode: Int, Sendable {
        case originalLinks = 0
        case endnotes = 1
        case pageFootnotes = 2
    }
    enum LayoutError: LocalizedError, Equatable {
        case noPrintableArea
        case outsidePrinterArea(PrintPageMargins)

        var errorDescription: String? {
            switch self {
            case .noPrintableArea:
                return "The selected paper size and margins leave no printable area."
            case .outsidePrinterArea(let required):
                return String(format: "This printer requires at least %.1f pt top, %.1f pt right, %.1f pt bottom and %.1f pt left margins. Adjust the layout margins or choose another printer.", required.top, required.right, required.bottom, required.left)
            }
        }
    }

    var margins: PrintPageMargins
    var fontSize: Double
    var lineSpacing: Double
    var includeExternalLinkReferences: Bool
    var citationMode: CitationMode? = nil
    var headingBreakLevel: Int = 0

    var effectiveCitationMode: CitationMode {
        citationMode ?? (includeExternalLinkReferences ? .endnotes : .originalLinks)
    }

    static let `default` = Self(
        margins: PrintPageMargins(top: 54, right: 54, bottom: 54, left: 54),
        fontSize: 12,
        lineSpacing: 1.45,
        includeExternalLinkReferences: false,
        citationMode: .pageFootnotes
    )

    var normalized: Self {
        let defaults = Self.default
        return Self(
            margins: margins.clamped(),
            fontSize: Self.clamp(fontSize, range: 8...24, fallback: defaults.fontSize),
            lineSpacing: Self.clamp(lineSpacing, range: 1...3, fallback: defaults.lineSpacing),
            includeExternalLinkReferences: includeExternalLinkReferences,
            citationMode: citationMode,
            headingBreakLevel: min(6, max(0, headingBreakLevel))
        )
    }

    func applying(to printInfo: NSPrintInfo) -> NSPrintInfo {
        let normalized = normalized
        let copy = (printInfo.copy() as? NSPrintInfo) ?? printInfo
        copy.topMargin = normalized.margins.top
        copy.rightMargin = normalized.margins.right
        copy.bottomMargin = normalized.margins.bottom
        copy.leftMargin = normalized.margins.left
        copy.isHorizontallyCentered = false
        copy.isVerticallyCentered = false
        return copy
    }

    func validate(for paperSize: NSSize) throws {
        let normalized = normalized
        let printableWidth = paperSize.width - normalized.margins.left - normalized.margins.right
        let printableHeight = paperSize.height - normalized.margins.top - normalized.margins.bottom
        guard printableWidth > 0, printableHeight > 0 else {
            throw LayoutError.noPrintableArea
        }
    }

    func validatePrintableArea(paperSize: NSSize, imageableBounds: CGRect) throws {
        try validate(for: paperSize)
        guard !imageableBounds.isEmpty, !imageableBounds.isInfinite else { throw LayoutError.noPrintableArea }
        let required = PrintPageMargins(
            top: max(0, paperSize.height - imageableBounds.maxY),
            right: max(0, paperSize.width - imageableBounds.maxX),
            bottom: max(0, imageableBounds.minY),
            left: max(0, imageableBounds.minX)
        )
        let margins = normalized.margins
        guard margins.top >= required.top, margins.right >= required.right,
              margins.bottom >= required.bottom, margins.left >= required.left else {
            throw LayoutError.outsidePrinterArea(required)
        }
    }

    private static func clamp(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

protocol PrintLayoutPreferenceStore {
    func double(forKey key: String) -> Double?
    func bool(forKey key: String) -> Bool?
    func set(_ value: Double, forKey key: String)
    func set(_ value: Bool, forKey key: String)
}

struct PrintLayoutSettingsStore {
    private enum Key {
        static let topMargin = "ouro.printLayout.margin.top"
        static let rightMargin = "ouro.printLayout.margin.right"
        static let bottomMargin = "ouro.printLayout.margin.bottom"
        static let leftMargin = "ouro.printLayout.margin.left"
        static let fontSize = "ouro.printLayout.fontSize"
        static let lineSpacing = "ouro.printLayout.lineSpacing"
        static let includeExternalLinks = "ouro.printLayout.includeExternalLinks"
        static let citationMode = "ouro.printLayout.citationMode"
        static let headingBreakLevel = "ouro.printLayout.headingBreakLevel"
    }

    let preferences: PrintLayoutPreferenceStore

    init(preferences: PrintLayoutPreferenceStore = UserDefaults.standard) {
        self.preferences = preferences
    }

    func load() -> PrintLayoutSettings {
        let defaults = PrintLayoutSettings.default
        return PrintLayoutSettings(
            margins: PrintPageMargins(
                top: preferences.double(forKey: Key.topMargin) ?? defaults.margins.top,
                right: preferences.double(forKey: Key.rightMargin) ?? defaults.margins.right,
                bottom: preferences.double(forKey: Key.bottomMargin) ?? defaults.margins.bottom,
                left: preferences.double(forKey: Key.leftMargin) ?? defaults.margins.left
            ),
            fontSize: preferences.double(forKey: Key.fontSize) ?? defaults.fontSize,
            lineSpacing: preferences.double(forKey: Key.lineSpacing) ?? defaults.lineSpacing,
            includeExternalLinkReferences: preferences.bool(forKey: Key.includeExternalLinks) ?? defaults.includeExternalLinkReferences,
            citationMode: preferences.double(forKey: Key.citationMode).flatMap { $0.isFinite && (0...2).contains($0) ? PrintLayoutSettings.CitationMode(rawValue: Int($0)) : nil } ?? .pageFootnotes,
            headingBreakLevel: Int(preferences.double(forKey: Key.headingBreakLevel).map { $0.isFinite && (0...6).contains($0) ? $0 : 0 } ?? 0)
        ).normalized
    }

    func save(_ settings: PrintLayoutSettings) {
        let normalized = settings.normalized
        preferences.set(normalized.margins.top, forKey: Key.topMargin)
        preferences.set(normalized.margins.right, forKey: Key.rightMargin)
        preferences.set(normalized.margins.bottom, forKey: Key.bottomMargin)
        preferences.set(normalized.margins.left, forKey: Key.leftMargin)
        preferences.set(normalized.fontSize, forKey: Key.fontSize)
        preferences.set(normalized.lineSpacing, forKey: Key.lineSpacing)
        preferences.set(normalized.includeExternalLinkReferences, forKey: Key.includeExternalLinks)
        preferences.set(Double(normalized.effectiveCitationMode.rawValue), forKey: Key.citationMode)
        preferences.set(Double(normalized.headingBreakLevel), forKey: Key.headingBreakLevel)
    }
}

extension UserDefaults: PrintLayoutPreferenceStore {
    func double(forKey key: String) -> Double? {
        object(forKey: key) as? Double
    }

    func bool(forKey key: String) -> Bool? {
        object(forKey: key) as? Bool
    }
}
