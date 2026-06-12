import SwiftUI

enum SidebarMode: String {
    case outline
    case files
}

struct OutlineItem: Identifiable {
    let id = UUID()
    let index: Int
    let level: Int
    let text: String
}

struct FolderItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let isCurrent: Bool
}

/// Left sidebar: document outline (from rendered headings) or the file's folder.
struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(get: { model.sidebarMode }, set: { model.setSidebarMode($0) })) {
                Text("Outline").tag(SidebarMode.outline)
                Text("Files").tag(SidebarMode.files)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            if model.sidebarMode == .outline {
                outlineList
            } else {
                fileList
            }
        }
        .frame(minWidth: 190)
    }

    @ViewBuilder private var outlineList: some View {
        if model.outlineItems.isEmpty {
            placeholder("No headings")
        } else {
            List(model.outlineItems) { item in
                Text(item.text.isEmpty ? "Untitled" : item.text)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectHeading(index: item.index) }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder private var fileList: some View {
        if model.folderItems.isEmpty {
            placeholder("No folder")
        } else {
            List(model.folderItems) { item in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(item.name).lineLimit(1)
                }
                .fontWeight(item.isCurrent ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.openFolderItem(item) }
            }
            .listStyle(.sidebar)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// The editor surface plus an optional find bar overlay.
struct EditorPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EditorWebView(model: model)
            if model.findVisible {
                FindBar(model: model)
                    .padding([.top, .trailing], 10)
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}

private struct FindBar: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
            TextField("Find", text: Binding(get: { model.findQuery }, set: { model.setFindQuery($0) }))
                .textFieldStyle(.plain)
                .frame(width: 170)
                .focused($focused)
                .onSubmit { model.findNext() }
            Button { model.findPrev() } label: { Image(systemName: "chevron.up") }.buttonStyle(.plain)
            Button { model.findNext() } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
            Button { model.closeFind() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
        .onAppear { focused = true }
    }
}
