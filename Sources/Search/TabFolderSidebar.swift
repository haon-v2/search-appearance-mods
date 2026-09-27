import SwiftUI
import UniformTypeIdentifiers

private let folderDragType = "local.noah.search.tab-folder-tab"

struct FolderSidebarRows: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var folders: TabFolderStore
    let pill: Namespace.ID
    private var loose: [Tab] { browser.tabs.filter { $0.pin == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Open Tabs").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer()
                Menu {
                    Button("New Folder…") { browser.editFolder() }
                    Divider()
                    Button("Import Folders…") { browser.chooseFolderImport() }
                    Button("Export Folders…") { browser.chooseFolderExport() }
                } label: { Image(systemName: "folder.badge.plus").frame(width: 26, height: 26) }
                .menuStyle(.borderlessButton).fixedSize().help("Tab folders")
            }
            .padding(.leading, 8)
            .contentShape(Rectangle())
            .onDrop(of: [folderDragType], delegate: FolderDrop(browser: browser, folderID: nil))
            ForEach(loose.filter { folders.valid($0.folderID, in: browser.spaceID) == nil }) { tab in
                row(tab).padding(.leading, 12)
            }
            ForEach(folders.folders(in: browser.spaceID)) { folder in
                FolderSection(browser: browser, prefs: prefs, folder: folder,
                              tabs: loose.filter { $0.folderID == folder.id }, pill: pill)
            }
        }
    }
    private func row(_ tab: Tab) -> some View {
        SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == browser.activeID,
                pill: pill, close: { browser.close(tab) })
            .modifier(FolderDrag(browser: browser, tab: tab))
    }
}

private struct FolderSection: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    let folder: TabFolder
    let tabs: [Tab]
    let pill: Namespace.ID
    @State private var hover: UUID?
    @State private var targeted = false
    private var hookHeight: CGFloat? {
        guard let hover, let index = tabs.firstIndex(where: { $0.id == hover }) else { return nil }
        return CGFloat(index) * 30 + 14
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                browser.folderAction { try browser.tabFolders.collapse(folder.id, !folder.collapsed) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder").frame(width: 16)
                    Text(folder.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(tabs.count)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Image(systemName: folder.collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 14)
                }
                .foregroundStyle(Palette.ink).padding(.horizontal, 8).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(targeted ? Palette.hover : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .onHover { if $0 { hover = nil } }
            .contextMenu {
                Button("New Tab in Folder") { browser.newTab(inFolder: folder.id) }
                Button("Rename Folder…") { browser.editFolder(folder) }
                Button("Remove Folder — Keep Tabs") { browser.folderAction { try browser.removeFolder(folder.id) } }
            }
            .onDrop(of: [folderDragType], delegate: FolderDrop(browser: browser, folderID: folder.id, targeted: $targeted))
            if !folder.collapsed {
                VStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        SideRow(browser: browser, prefs: prefs, tab: tab, live: tab.id == browser.activeID,
                                pill: pill, close: { browser.close(tab) })
                            .modifier(FolderDrag(browser: browser, tab: tab))
                            .onHover { on in
                                if on { hover = tab.id } else if hover == tab.id { hover = nil }
                            }
                    }
                }
                .padding(.leading, 24)
                .overlay(alignment: .topLeading) {
                    if let height = hookHeight {
                        Path { p in
                            p.move(to: CGPoint(x: 15, y: -2))
                            p.addLine(to: CGPoint(x: 15, y: max(0, height - 5)))
                            p.addQuadCurve(to: CGPoint(x: 20, y: height), control: CGPoint(x: 15, y: height))
                            p.addLine(to: CGPoint(x: 24, y: height))
                        }
                        .stroke(Palette.muted, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [1, 4]))
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

private struct FolderDrag: ViewModifier {
    let browser: Browser
    let tab: Tab
    func body(content: Content) -> some View {
        if tab.shy { content } else {
            content.onDrag {
                let provider = NSItemProvider()
                let data = Data("\(browser.folderDragNonce.uuidString):\(tab.id.uuidString)".utf8)
                provider.registerDataRepresentation(forTypeIdentifier: folderDragType, visibility: .ownProcess) { reply in
                    reply(data, nil); return nil
                }
                return provider
            }
        }
    }
}

/// Only a drag originating in this browser and its current space can move a tab.
struct FolderDrop: DropDelegate {
    let browser: Browser
    let folderID: UUID?
    var targeted: Binding<Bool>?
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [folderDragType]) }
    func dropEntered(info: DropInfo) { targeted?.wrappedValue = true }
    func dropExited(info: DropInfo) { targeted?.wrappedValue = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        targeted?.wrappedValue = false
        guard let provider = info.itemProviders(for: [folderDragType]).first else { return false }
        let space = browser.spaceID
        provider.loadDataRepresentation(forTypeIdentifier: folderDragType) { data, _ in
            guard let data, data.count <= 100, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard browser.spaceID == space else { return }
                browser.folderAction { try browser.receiveFolderDrop(text, folderID: folderID) }
            }
        }
        return true
    }
}

extension Browser {
    func receiveFolderDrop(_ payload: String, folderID: UUID?) throws {
        let parts = payload.split(separator: ":")
        guard parts.count == 2, parts[0] == Substring(folderDragNonce.uuidString),
              let id = UUID(uuidString: String(parts[1])), let tab = tabs.first(where: { $0.id == id }) else {
            throw ModError.invalid("This tab belongs to another window or space.")
        }
        try moveToFolder(tab, folderID)
    }
}

struct FolderTabMenu: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    var body: some View {
        if AppearanceMods.shared.usesSidebarFolders, !tab.shy, tab.pin == nil {
            Menu("Move to Folder") {
                Button("Open Tabs") { browser.folderAction { try browser.moveToFolder(tab, nil) } }
                ForEach(browser.tabFolders.folders(in: browser.spaceID)) { folder in
                    Button(folder.name) { browser.folderAction { try browser.moveToFolder(tab, folder.id) } }
                }
                Divider()
                Button("New Folder…") { browser.editFolder(moving: tab) }
            }
            Divider()
        }
    }
}
