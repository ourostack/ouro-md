import AppKit
import Foundation

@MainActor
final class PrintLayoutAccessoryController: NSViewController {
    enum ValidationError: LocalizedError, Equatable {
        case invalidNumber(String)
        case outOfRange(String, ClosedRange<Double>)

        var errorDescription: String? {
            switch self {
            case .invalidNumber(let label):
                return "\(label) must be a finite number."
            case .outOfRange(let label, let range):
                return "\(label) must be between \(Self.display(range.lowerBound)) and \(Self.display(range.upperBound))."
            }
        }

        private static func display(_ value: Double) -> String {
            String(format: value.rounded() == value ? "%.0f" : "%.2f", value)
        }
    }

    var onSettingsChanged: ((PrintLayoutSettings) -> Void)?

    private let settingsStore: PrintLayoutSettingsStore
    private(set) var currentSettings: PrintLayoutSettings
    private(set) var validationMessage: String?

    private let topField = NSTextField(string: "")
    private let rightField = NSTextField(string: "")
    private let bottomField = NSTextField(string: "")
    private let leftField = NSTextField(string: "")
    private let fontSizeField = NSTextField(string: "")
    private let lineSpacingField = NSTextField(string: "")
    private let externalLinksCheckbox = NSButton(checkboxWithTitle: "Number external links at the end", target: nil, action: nil)
    private let validationLabel = NSTextField(labelWithString: "")

    init(settings: PrintLayoutSettings, settingsStore: PrintLayoutSettingsStore = PrintLayoutSettingsStore()) {
        self.currentSettings = settings.normalized
        self.settingsStore = settingsStore
        super.init(nibName: nil, bundle: nil)
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

        validationLabel.textColor = .systemRed
        validationLabel.lineBreakMode = .byWordWrapping
        validationLabel.maximumNumberOfLines = 0
        validationLabel.setAccessibilityLabel("Print layout validation")

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

        let stack = NSStackView(views: [grid, externalLinksCheckbox, validationLabel])
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
            topField.widthAnchor.constraint(equalToConstant: 80),
            rightField.widthAnchor.constraint(equalToConstant: 80),
            bottomField.widthAnchor.constraint(equalToConstant: 80),
            leftField.widthAnchor.constraint(equalToConstant: 80),
            fontSizeField.widthAnchor.constraint(equalToConstant: 80),
            lineSpacingField.widthAnchor.constraint(equalToConstant: 80),
            validationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        view = container
        syncView(from: currentSettings)
        updateValidationMessage(nil)
    }

    func applyCurrentValues() -> Bool {
        do {
            let updated = try validatedSettingsFromFields().normalized
            currentSettings = updated
            settingsStore.save(updated)
            syncView(from: updated)
            updateValidationMessage(nil)
            onSettingsChanged?(updated)
            return true
        } catch {
            updateValidationMessage((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    func setFieldValues(
        top: String,
        right: String,
        bottom: String,
        left: String,
        fontSize: String,
        lineSpacing: String,
        includeExternalLinks: Bool
    ) {
        topField.stringValue = top
        rightField.stringValue = right
        bottomField.stringValue = bottom
        leftField.stringValue = left
        fontSizeField.stringValue = fontSize
        lineSpacingField.stringValue = lineSpacing
        externalLinksCheckbox.state = includeExternalLinks ? .on : .off
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

    private func updateValidationMessage(_ message: String?) {
        validationMessage = message
        validationLabel.stringValue = message ?? ""
        validationLabel.isHidden = (message == nil)
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        _ = applyCurrentValues()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        _ = applyCurrentValues()
    }

    private func validatedSettingsFromFields() throws -> PrintLayoutSettings {
        PrintLayoutSettings(
            margins: PrintPageMargins(
                top: try parseField(topField.stringValue, label: "Top margin", range: 18...144),
                right: try parseField(rightField.stringValue, label: "Right margin", range: 18...144),
                bottom: try parseField(bottomField.stringValue, label: "Bottom margin", range: 18...144),
                left: try parseField(leftField.stringValue, label: "Left margin", range: 18...144)
            ),
            fontSize: try parseField(fontSizeField.stringValue, label: "Font size", range: 8...24),
            lineSpacing: try parseField(lineSpacingField.stringValue, label: "Line spacing", range: 1...3),
            includeExternalLinkReferences: externalLinksCheckbox.state == .on
        )
    }

    private func parseField(_ value: String, label: String, range: ClosedRange<Double>) throws -> Double {
        guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), parsed.isFinite else {
            throw ValidationError.invalidNumber(label)
        }
        guard range.contains(parsed) else {
            throw ValidationError.outOfRange(label, range)
        }
        return parsed
    }

    private func numberString(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func lineSpacingString(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
