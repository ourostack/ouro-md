import AppKit
import Foundation

@MainActor
final class PrintLayoutAccessoryController: NSViewController, NSPrintPanelAccessorizing {
    var onSettingsChanged: ((PrintLayoutSettings) -> Void)?

    private let settingsStore: PrintLayoutSettingsStore
    private(set) var currentSettings: PrintLayoutSettings

    private let topField = NSTextField(string: "")
    private let rightField = NSTextField(string: "")
    private let bottomField = NSTextField(string: "")
    private let leftField = NSTextField(string: "")
    private let fontSizeField = NSTextField(string: "")
    private let lineSpacingField = NSTextField(string: "")
    private let externalLinksCheckbox = NSButton(checkboxWithTitle: "Number external links at the end", target: nil, action: nil)

    init(settings: PrintLayoutSettings, settingsStore: PrintLayoutSettingsStore = PrintLayoutSettingsStore()) {
        self.currentSettings = settings.normalized
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
        representedObject = self.currentSettings.applying(to: .shared)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        configureField(topField, title: "Top margin (pt)")
        configureField(rightField, title: "Right margin (pt)")
        configureField(bottomField, title: "Bottom margin (pt)")
        configureField(leftField, title: "Left margin (pt)")
        configureField(fontSizeField, title: "Font size (pt)")
        configureField(lineSpacingField, title: "Line spacing")

        externalLinksCheckbox.target = self
        externalLinksCheckbox.action = #selector(checkboxChanged(_:))
        externalLinksCheckbox.setAccessibilityLabel("Number external links at the end")

        let grid = NSGridView(views: [
            [labeled("Top margin (pt)"), topField],
            [labeled("Right margin (pt)"), rightField],
            [labeled("Bottom margin (pt)"), bottomField],
            [labeled("Left margin (pt)"), leftField],
            [labeled("Font size (pt)"), fontSizeField],
            [labeled("Line spacing"), lineSpacingField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.yPlacement = .center
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let stack = NSStackView(views: [grid, externalLinksCheckbox])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            topField.widthAnchor.constraint(equalToConstant: 72),
            rightField.widthAnchor.constraint(equalToConstant: 72),
            bottomField.widthAnchor.constraint(equalToConstant: 72),
            leftField.widthAnchor.constraint(equalToConstant: 72),
            fontSizeField.widthAnchor.constraint(equalToConstant: 72),
            lineSpacingField.widthAnchor.constraint(equalToConstant: 72),
        ])
        view = container
        syncView(from: currentSettings)
    }

    private func configureField(_ field: NSTextField, title: String) {
        field.alignment = .right
        field.target = self
        field.action = #selector(fieldChanged(_:))
        field.setAccessibilityLabel(title)
    }

    private func labeled(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        return label
    }

    private func syncView(from settings: PrintLayoutSettings) {
        topField.stringValue = numberString(settings.margins.top)
        rightField.stringValue = numberString(settings.margins.right)
        bottomField.stringValue = numberString(settings.margins.bottom)
        leftField.stringValue = numberString(settings.margins.left)
        fontSizeField.stringValue = numberString(settings.fontSize)
        lineSpacingField.stringValue = lineSpacingString(settings.lineSpacing)
        externalLinksCheckbox.state = settings.includeExternalLinkReferences ? .on : .off
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        applyCurrentValues()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        applyCurrentValues()
    }

    private func applyCurrentValues() {
        let updated = PrintLayoutSettings(
            margins: PrintPageMargins(
                top: parsedNumber(topField.stringValue, fallback: currentSettings.margins.top),
                right: parsedNumber(rightField.stringValue, fallback: currentSettings.margins.right),
                bottom: parsedNumber(bottomField.stringValue, fallback: currentSettings.margins.bottom),
                left: parsedNumber(leftField.stringValue, fallback: currentSettings.margins.left)
            ),
            fontSize: parsedNumber(fontSizeField.stringValue, fallback: currentSettings.fontSize),
            lineSpacing: parsedNumber(lineSpacingField.stringValue, fallback: currentSettings.lineSpacing),
            includeExternalLinkReferences: externalLinksCheckbox.state == .on
        ).normalized
        currentSettings = updated
        settingsStore.save(updated)
        representedObject = updated.applying(to: .shared)
        syncView(from: updated)
        onSettingsChanged?(updated)
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[
            .itemName: "Print layout",
            .itemDescription: summaryDescription(for: currentSettings)
        ]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        [
            "representedObject.topMargin",
            "representedObject.rightMargin",
            "representedObject.bottomMargin",
            "representedObject.leftMargin"
        ]
    }

    private func summaryDescription(for settings: PrintLayoutSettings) -> String {
        let margins = settings.margins
        return "Margins \(numberString(margins.top))/\(numberString(margins.right))/\(numberString(margins.bottom))/\(numberString(margins.left)) pt, font \(numberString(settings.fontSize)) pt, line spacing \(lineSpacingString(settings.lineSpacing))"
    }

    private func parsedNumber(_ value: String, fallback: Double) -> Double {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback
    }

    private func numberString(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func lineSpacingString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
