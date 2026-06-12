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

/// Left sidebar: document outline (from rendered headings) or the mounted folder.
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
                FolderBrowserView(model: model)
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

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Typora-style file browser for the mounted folder: filename filter, tree or
/// list view, and a footer showing the folder name + new-file + view toggle.
struct FolderBrowserView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search by file name", text: Binding(
                    get: { model.folderFilter }, set: { model.folderFilter = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.folderFilter.isEmpty {
                    Button { model.folderFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()

            content

            Divider()
            footer
        }
    }

    @ViewBuilder private var content: some View {
        if model.mountedFolder == nil {
            centered("No folder open", action: "Open Folder…") { model.openFolderPanel() }
        } else if !model.folderFilter.isEmpty {
            if model.filteredFolderFiles.isEmpty {
                centered("No matching files", action: nil, perform: nil)
            } else {
                List(model.filteredFolderFiles) { fileRow($0, showParent: true) }.listStyle(.sidebar)
            }
        } else if model.useTreeView {
            List(model.folderTree, children: \.children) { node in nodeRow(node) }.listStyle(.sidebar)
        } else if model.folderFlat.isEmpty {
            centered("No markdown files here", action: nil, perform: nil)
        } else {
            List(model.folderFlat) { fileRow($0, showParent: false) }.listStyle(.sidebar)
        }
    }

    @ViewBuilder private func nodeRow(_ node: FolderNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder").font(.system(size: 12)).lineLimit(1)
        } else {
            fileRow(node, showParent: false)
        }
    }

    private func fileRow(_ node: FolderNode, showParent: Bool) -> some View {
        let isCurrent = node.url == model.currentURL
        return HStack(spacing: 6) {
            Image(systemName: "doc.text").foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name).font(.system(size: 12)).lineLimit(1)
                if showParent, let folder = model.mountedFolder {
                    Text(parentHint(node.url, under: folder))
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .fontWeight(isCurrent ? .semibold : .regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.openFile(node.url) }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button { model.toggleFolderView() } label: {
                Image(systemName: model.useTreeView ? "list.bullet" : "list.bullet.indent")
            }
            .buttonStyle(.plain)
            .help(model.useTreeView ? "Switch to File List view" : "Switch to File Tree view")

            Spacer(minLength: 0)
            Button { model.openFolderPanel() } label: {
                Text(model.mountedFolderName).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)

            Menu {
                ForEach(FolderSort.allCases, id: \.self) { sort in
                    Button { model.setFolderSort(sort) } label: {
                        Label(sort.label, systemImage: model.folderSort == sort ? "checkmark" : "")
                    }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
            .menuStyle(.borderlessButton).frame(width: 22)
            .help("Sort")

            Button { model.newFileInMountedFolder() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("New File")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func parentHint(_ url: URL, under folder: URL) -> String {
        let rel = url.deletingLastPathComponent().path.replacingOccurrences(of: folder.path, with: "")
        let trimmed = rel.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? folder.lastPathComponent : trimmed
    }

    @ViewBuilder private func centered(_ text: String, action: String?, perform: (() -> Void)?) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text).font(.system(size: 12)).foregroundStyle(.tertiary)
            if let action, let perform {
                Button(action, action: perform).buttonStyle(.link).font(.system(size: 12))
            }
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
