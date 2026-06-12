import SwiftUI

/// Full-bleed editor surface; the native window provides all chrome.
struct ContentView: View {
    let model: AppModel

    var body: some View {
        EditorWebView(model: model)
            .ignoresSafeArea()
            .frame(minWidth: 480, minHeight: 360)
    }
}

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
