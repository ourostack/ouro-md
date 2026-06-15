import SwiftUI

/// Word-count popover content (Typora-style "Toggle Word Count").
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

/// Minimal preferences sheet: default theme, auto-save, text size.
struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateCoordinator: OuroMDUpdateCoordinator
    @ObservedObject var telemetry: OuroMDTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Preferences").font(.system(size: 15, weight: .semibold))

            HStack {
                Text("Theme").frame(width: 90, alignment: .leading)
                Picker("", selection: Binding(get: { model.themeID }, set: { model.setTheme(id: $0) })) {
                    ForEach(ThemeStore.shared.themes) { Text($0.displayName).tag($0.id) }
                }
                .labelsHidden()
            }

            HStack {
                Text("Auto-save").frame(width: 90, alignment: .leading)
                Toggle("Save changes automatically", isOn: Binding(get: { model.autoSaveEnabled }, set: { model.setAutoSave($0) }))
                Spacer()
            }

            HStack {
                Text("Auto-pair").frame(width: 90, alignment: .leading)
                Toggle("Close brackets and quotes automatically", isOn: Binding(get: { model.autoPairEnabled }, set: { model.setAutoPair($0) }))
                Spacer()
            }

            HStack {
                Text("Updates").frame(width: 90, alignment: .leading)
                Toggle("Check for updates automatically", isOn: Binding(get: { updateCoordinator.autoUpdateEnabled }, set: { updateCoordinator.setAutoUpdateEnabled($0) }))
                Spacer()
            }

            HStack {
                Text("Telemetry").frame(width: 90, alignment: .leading)
                Toggle("Share anonymous usage telemetry", isOn: Binding(get: { telemetry.isEnabled }, set: { telemetry.setEnabled($0) }))
                    .disabled(!telemetry.isConfigured)
                Spacer()
            }

            HStack {
                Text("Text size").frame(width: 90, alignment: .leading)
                Slider(value: Binding(get: { model.zoom }, set: { model.setTextScale($0) }), in: 0.7...2.0, step: 0.1)
                Text("\(Int((model.zoom * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
