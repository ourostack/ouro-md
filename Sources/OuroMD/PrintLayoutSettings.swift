import AppKit
import Foundation

struct PrintPageMargins: Equatable, Sendable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    func clamped() -> Self {
        Self(
            top: Self.clamp(top),
            right: Self.clamp(right),
            bottom: Self.clamp(bottom),
            left: Self.clamp(left)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(144, max(18, value))
    }
}

struct PrintLayoutSettings: Equatable, Sendable {
    var margins: PrintPageMargins
    var fontSize: Double
    var lineSpacing: Double
    var includeExternalLinkReferences: Bool

    static let `default` = Self(
        margins: PrintPageMargins(top: 54, right: 54, bottom: 54, left: 54),
        fontSize: 12,
        lineSpacing: 1.45,
        includeExternalLinkReferences: true
    )

    var normalized: Self {
        Self(
            margins: margins.clamped(),
            fontSize: min(24, max(8, fontSize)),
            lineSpacing: min(3, max(1, lineSpacing)),
            includeExternalLinkReferences: includeExternalLinkReferences
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
            includeExternalLinkReferences: preferences.bool(forKey: Key.includeExternalLinks) ?? defaults.includeExternalLinkReferences
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

final class InMemoryPrintLayoutPreferenceStore: PrintLayoutPreferenceStore {
    private var doubles: [String: Double] = [:]
    private var bools: [String: Bool] = [:]

    func double(forKey key: String) -> Double? { doubles[key] }
    func bool(forKey key: String) -> Bool? { bools[key] }
    func set(_ value: Double, forKey key: String) { doubles[key] = value }
    func set(_ value: Bool, forKey key: String) { bools[key] = value }
}
