import Foundation
import Combine

/// Port of Curve's TabFolder model. Membership lives in each tab's session;
/// folder names and collapse state belong to a Search space, never a website.
struct TabFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let spaceID: UUID
    var collapsed: Bool
}

@MainActor final class TabFolderStore: ObservableObject {
    @Published private(set) var items: [TabFolder] = []
    let file: URL
    init(file: URL = Store.file("tab-folders.json")) {
        self.file = file
        guard let data = try? Data(contentsOf: file) else { return }
        guard data.count <= 1_048_576,
              let decoded = try? JSONDecoder().decode([TabFolder].self, from: data),
              Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 80 }),
              Dictionary(grouping: decoded, by: \.spaceID).values.allSatisfy({ $0.count <= 64 })
        else { Store.quarantine(file); return }
        items = decoded
    }
    func folders(in space: UUID) -> [TabFolder] { items.filter { $0.spaceID == space } }
    func valid(_ id: UUID?, in space: UUID) -> UUID? {
        items.first { $0.id == id && $0.spaceID == space }?.id
    }
    private func commit(_ next: [TabFolder]) throws {
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        items = next
    }
    @discardableResult func create(_ name: String, in space: UUID) throws -> UUID {
        guard folders(in: space).count < 64 else { throw ModError.invalid("A space can hold up to 64 folders.") }
        let folder = TabFolder(id: UUID(), name: try Self.name(name), spaceID: space, collapsed: false)
        try commit(items + [folder]); return folder.id
    }
    static func name(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw ModError.invalid("Use a folder name between 1 and 80 characters.") }
        return name
    }
    func rename(_ id: UUID, to name: String) throws {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var next = items; next[i].name = try Self.name(name); try commit(next)
    }
    func collapse(_ id: UUID, _ collapsed: Bool) throws {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].collapsed != collapsed else { return }
        var next = items; next[i].collapsed = collapsed; try commit(next)
    }
    func remove(_ id: UUID) throws { try commit(items.filter { $0.id != id }) }
}

/// Same JSON shape exported by Curve. Extra bookmark fields are ignored.
struct ImportedTabFolder: Codable {
    struct Entry: Codable { var title: String; var url: String }
    var name: String
    var tabs: [Entry]
}
