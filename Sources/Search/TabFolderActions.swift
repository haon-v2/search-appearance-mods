import AppKit
import UniformTypeIdentifiers

extension Browser {
    var folderTabs: [Tab] {
        guard AppearanceMods.shared.usesSidebarFolders else { return tabs }
        return tabs.filter { $0.folderID == active?.folderID }
    }
    func folderAction(_ action: () throws -> Void) {
        do { try action() } catch { announce(error.localizedDescription) }
    }
    func editFolder(_ folder: TabFolder? = nil, moving tab: Tab? = nil) {
        guard let window = Links.window else { return }
        let alert = NSAlert()
        alert.messageText = folder == nil ? "New Folder" : "Rename Folder"
        let field = NSTextField(string: folder?.name ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.placeholderString = "Folder name"
        alert.accessoryView = field
        alert.addButton(withTitle: folder == nil ? "Create" : "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let space = spaceID
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, let self, self.spaceID == space else { return }
            self.folderAction {
                if let folder { try self.tabFolders.rename(folder.id, to: field.stringValue) }
                else {
                    let id = try self.tabFolders.create(field.stringValue, in: space)
                    if let tab { try self.moveToFolder(tab, id) }
                }
            }
        }
    }
    func moveToFolder(_ tab: Tab, _ id: UUID?) throws {
        guard AppearanceMods.shared.usesSidebarFolders, !tab.shy, tab.pin == nil,
              tabs.contains(where: { $0.id == tab.id }),
              id == nil || tabFolders.valid(id, in: spaceID) != nil else {
            throw ModError.invalid("Choose an ordinary tab and a folder in the current space.")
        }
        if let id { try tabFolders.collapse(id, false) }
        objectWillChange.send()
        tab.folderID = id
        writeSession(now: true)
    }
    func removeFolder(_ id: UUID) throws {
        guard tabFolders.valid(id, in: spaceID) != nil else { return }
        try tabFolders.remove(id)
        for tab in tabs where tab.folderID == id { tab.folderID = nil }
        writeSession(now: true)
    }
    func newTab(inFolder id: UUID) {
        guard tabFolders.valid(id, in: spaceID) != nil else { return }
        let tab = Tab()
        tab.folderID = id
        prepare(tab); insert(tab, at: tabs.count); select(tab)
        folderAction { try tabFolders.collapse(id, false) }
    }
    /// Imports stay asleep: no site is contacted merely by importing a file.
    @discardableResult func importFolders(_ data: Data) throws -> Int {
        guard data.count <= 1_048_576 else { throw ModError.invalid("Folder imports must be smaller than 1 MB.") }
        let groups = try JSONDecoder().decode([ImportedTabFolder].self, from: data)
        guard groups.count <= 64, groups.reduce(0, { $0 + $1.tabs.count }) <= 100 else {
            throw ModError.invalid("Import at most 64 folders and 100 tabs at a time.")
        }
        for group in groups { _ = try TabFolderStore.name(group.name) }
        let current = tabFolders.folders(in: spaceID)
        let addedNames = Set(groups.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            .subtracting(Set(current.map(\.name)))
        guard current.count + addedNames.count <= 64 else { throw ModError.invalid("This space would exceed 64 folders.") }
        var count = 0
        for group in groups {
            let name = try TabFolderStore.name(group.name)
            let id = try tabFolders.folders(in: spaceID).first(where: { $0.name == name })?.id
                ?? tabFolders.create(name, in: spaceID)
            for entry in group.tabs {
                guard let url = URL(string: entry.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      url.host != nil, url.user == nil, url.password == nil,
                      !tabs.contains(where: { $0.folderID == id && ($0.pending ?? $0.address) == url }) else { continue }
                let tab = Tab(configuration: Web.configuration(space: spaceID))
                tab.folderID = id
                tab.restore(url: url, title: String(entry.title.prefix(300)), name: nil)
                prepare(tab); insert(tab, at: tabs.count); count += 1
            }
        }
        writeSession(now: true)
        return count
    }
    func exportFolders() throws -> Data {
        let groups = tabFolders.folders(in: spaceID).map { folder in
            ImportedTabFolder(name: folder.name, tabs: tabs.compactMap { tab in
                guard tab.folderID == folder.id, !tab.shy, !tab.bench,
                      let url = tab.pending ?? tab.address,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
                return .init(title: tab.label, url: url.absoluteString)
            })
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(groups)
    }
    func chooseFolderImport() {
        guard let window = Links.window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Import a Curve Tab Folders JSON export. Tabs stay asleep until selected."
        let space = spaceID
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.spaceID == space else { return }
            self.folderAction {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 1_048_576 else {
                    throw ModError.invalid("Choose a JSON file smaller than 1 MB.")
                }
                let count = try self.importFolders(Data(contentsOf: url))
                self.announce("Imported \(count) tabs")
            }
        }
    }
    func chooseFolderExport() {
        guard let window = Links.window else { return }
        do {
            let data = try exportFolders()
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Curve Tab Folders.json"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                self.folderAction {
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
            }
        } catch { announce(error.localizedDescription) }
    }
}
