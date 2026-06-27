import SwiftUI

/// Word-count popover content for the status/menu command.
struct WordCountView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            row("Words", model.wordCount)
            row("Characters", model.charCount)
        }
        .padding(16)
        .frame(width: 190)
    }

    private func row(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 12))
    }
}

/// Preferences sheet: theme/appearance, editing toggles, updates, telemetry,
/// and text size.
struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    @ObservedObject var telemetry: OuroMDTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.system(size: 15, weight: .semibold))

            preferenceRow("Appearance") {
                Picker("Appearance", selection: Binding(get: { appearanceSelection }, set: setAppearance(_:))) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
                .frame(width: 180)
            }

            preferenceRow("Theme") {
                Picker("Theme", selection: Binding(get: { model.themeID }, set: { model.setTheme(id: $0) })) {
                    ForEach(ThemeStore.shared.themes) { Text($0.displayName).tag($0.id) }
                }
                .labelsHidden()
                .accessibilityLabel("Theme")
                .frame(width: 220)
            }

            preferenceRow("Auto-save") {
                Toggle("Save changes automatically", isOn: Binding(get: { model.autoSaveEnabled }, set: { model.setAutoSave($0) }))
            }

            preferenceRow("Auto-pair") {
                Toggle("Close brackets and quotes automatically", isOn: Binding(get: { model.autoPairEnabled }, set: { model.setAutoPair($0) }))
            }

            preferenceRow("Updates") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Check for updates automatically", isOn: Binding(get: { updateCoordinator.autoUpdateEnabled }, set: { updateCoordinator.setAutoUpdateEnabled($0) }))
                    OuroMDReleaseControls(updateCoordinator: updateCoordinator, showTitle: false)
                }
            }

            preferenceRow("Telemetry") {
                Toggle("Share anonymous usage telemetry", isOn: Binding(get: { telemetry.isEnabled }, set: { telemetry.setEnabled($0) }))
                    .disabled(!telemetry.isConfigured)
            }

            preferenceRow("Text size") {
                HStack(spacing: 10) {
                    Slider(value: Binding(get: { model.zoom }, set: { model.setTextScale($0) }), in: 0.7...2.0, step: 0.1)
                        .frame(width: 190)
                        .accessibilityLabel("Text size")
                        .accessibilityValue("\(Int((model.zoom * 100).rounded())) percent")
                    Text("\(Int((model.zoom * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    Button("Actual Size") { model.actualSize() }
                        .controlSize(.small)
                }
            }
        }
        .font(.system(size: 12))
        .padding(24)
        .frame(minWidth: 500, idealWidth: 560)
    }

    private var appearanceSelection: String {
        model.theme.uiMode == "dark" ? "dark" : "light"
    }

    private func setAppearance(_ value: String) {
        model.setAppearance(value)
    }

    private func preferenceRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct UpdateProgressView: View {
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator

    var body: some View {
        let progress = updateCoordinator.installProgress
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                progressIcon(progress)
                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.title.isEmpty ? "Installing Update" : progress.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(progress.detail.isEmpty ? "Preparing update..." : progress.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                            .accessibilityLabel("Update progress")
                            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
                    }
                }
            }
            if progress.canCancel || progress.canRetry {
                HStack(spacing: 8) {
                    Spacer()
                    if progress.canCancel {
                        Button("Cancel") { updateCoordinator.cancelInstall() }
                            .controlSize(.small)
                            .accessibilityLabel("Cancel update")
                    }
                    if progress.canRetry {
                        Button("Retry") { updateCoordinator.startInstallReleaseUpdate() }
                            .controlSize(.small)
                            .keyboardShortcut(.defaultAction)
                            .accessibilityLabel("Retry update")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.title.isEmpty ? "Installing update" : progress.title)
        .accessibilityValue(progress.detail.isEmpty ? "Preparing update" : progress.detail)
        .padding(18)
        .frame(width: 400, alignment: .leading)
    }

    @ViewBuilder
    private func progressIcon(_ progress: OuroMDInstallProgress) -> some View {
        switch progress.phase {
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .ready:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        default:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Update progress")
        }
    }
}
