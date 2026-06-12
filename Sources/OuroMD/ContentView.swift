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
