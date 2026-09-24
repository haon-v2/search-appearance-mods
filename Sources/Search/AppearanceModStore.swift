import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Version 1 is data only. Layout names opt into renderers supplied by the
/// host; a mod cannot inject native code, scripts, CSS, URLs or permissions.
struct AppearanceMod: Codable, Equatable, Identifiable {
  enum Layout: String, Codable { case standard, edgeRail }
  struct Rail: Codable, Equatable {
    var cornerRadius: Double
    var tabLength: Double
    var gap: Double
  }
  struct Colors: Codable, Equatable {
    var light: [String: String]
    var dark: [String: String]
  }
  let schemaVersion: Int
  let id: String
  let name: String
  let author: String
  let summary: String
  let tabLayout: Layout
  let colors: Colors?
  let rail: Rail?
  static let maximumBytes = 65_536
  static let roles: Set<String> = ["ground", "ink", "muted", "faint", "hairline", "wash", "hover"]
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= maximumBytes else {
      throw ModError.invalid("The mod is larger than 64 KB.")
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(json.keys).isSubset(of: [
        "schemaVersion", "id", "name", "author", "summary", "tabLayout", "colors", "rail",
      ])
    else {
      throw ModError.invalid("Unknown mod fields. Only appearance settings are supported.")
    }
    let mod = try JSONDecoder().decode(Self.self, from: data)
    guard mod.schemaVersion == 1 else {
      throw ModError.invalid("This mod requires a different appearance API version.")
    }
    guard mod.id.range(of: "^[a-z][a-z0-9.-]{0,63}$", options: .regularExpression) != nil,
      !mod.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      mod.name.count <= 80, mod.author.count <= 80, mod.summary.count <= 300
    else {
      throw ModError.invalid("Invalid mod name, identifier, or description.")
    }
    if mod.tabLayout == .edgeRail {
      guard let rail = mod.rail,
        let object = json["rail"] as? [String: Any],
        Set(object.keys) == ["cornerRadius", "tabLength", "gap"],
        rail.cornerRadius.isFinite, (40...120).contains(rail.cornerRadius),
        rail.tabLength.isFinite, (120...300).contains(rail.tabLength),
        rail.gap.isFinite, (4...24).contains(rail.gap)
      else {
        throw ModError.invalid(
          "Edge rails require a radius of 40–120, tab length of 120–300, and gap of 4–24 points.")
      }
    } else if mod.rail != nil {
      throw ModError.invalid("Rail settings require the edgeRail layout.")
    }
    if let colors = mod.colors {
      guard let object = json["colors"] as? [String: Any], Set(object.keys) == ["light", "dark"]
      else { throw ModError.invalid("Colors need light and dark palettes.") }
      for palette in [colors.light, colors.dark] {
        guard Set(palette.keys).isSubset(of: roles),
          palette.values.allSatisfy({
            $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
          })
        else { throw ModError.invalid("Use supported color roles and six-digit hex colors.") }
      }
    }
    return mod
  }
}

enum ModError: LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    if case .invalid(let text) = self { return text }
    return nil
  }
}

/// Dynamic NSColors may resolve outside SwiftUI's main-actor update.
enum AppearanceColors {
  private static let lock = NSLock()
  private static var palette: AppearanceMod.Colors?
  static func set(_ value: AppearanceMod.Colors?) {
    lock.lock()
    defer { lock.unlock() }
    palette = value
  }
  static func color(role: String, dark: Bool) -> NSColor? {
    lock.lock()
    let hex = dark ? palette?.dark[role] : palette?.light[role]
    lock.unlock()
    guard let hex, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
    return NSColor(
      srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
      blue: CGFloat(value & 255) / 255, alpha: 1)
  }
}

@MainActor final class AppearanceMods: ObservableObject {
  static let shared = AppearanceMods()
  @Published private(set) var installed: [AppearanceMod] = []
  @Published private(set) var selectedID: String?
  @Published var notice =
    "Import a local appearance mod. Mods can change supported layouts and colors only."
  private let folder: URL
  private let defaults: UserDefaults
  var active: AppearanceMod? { installed.first { $0.id == selectedID } }
  var usesEdgeRail: Bool { active?.tabLayout == .edgeRail }
  init(folder: URL = Store.file("AppearanceMods"), defaults: UserDefaults = Store.settings) {
    self.folder = folder
    self.defaults = defaults
    selectedID = defaults.string(forKey: "appearance.mod")
    reload()
  }
  static func read(_ url: URL) throws -> Data {
    let values = try url.resourceValues(forKeys: [
      .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize,
      size <= AppearanceMod.maximumBytes
    else { throw ModError.invalid("Choose a regular JSON file no larger than 64 KB.") }
    return try Data(contentsOf: url)
  }
  func reload() {
    let files =
      (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
      ?? []
    var loaded: [AppearanceMod] = []
    for file in files.filter({ $0.pathExtension == "json" }).sorted(by: {
      $0.lastPathComponent < $1.lastPathComponent
    }).prefix(32) {
      if let data = try? Self.read(file), let mod = try? AppearanceMod.decode(data),
        file.lastPathComponent == mod.id + ".json"
      {
        loaded.append(mod)
      }
    }
    installed = loaded
    if selectedID != nil && active == nil {
      selectedID = nil
      defaults.removeObject(forKey: "appearance.mod")
      notice =
        "The selected mod could not be loaded. Search’s standard appearance has been restored."
    }
    AppearanceColors.set(active?.colors)
  }
  @discardableResult func install(_ url: URL) throws -> AppearanceMod {
    let data = try Self.read(url)
    let mod = try AppearanceMod.decode(data)
    guard !installed.contains(where: { $0.id == mod.id }) else {
      throw ModError.invalid(
        "That mod is already installed. Remove it before importing a replacement.")
    }
    guard installed.count < 32 else {
      throw ModError.invalid("Remove an unused mod before installing another.")
    }
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let destination = folder.appendingPathComponent(mod.id + ".json")
    guard !FileManager.default.fileExists(atPath: destination.path) else {
      throw ModError.invalid("A file with that identifier already exists.")
    }
    try data.write(to: destination, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: destination.path)
    reload()
    notice = "Installed \(mod.name). Choose Enable to apply it."
    return mod
  }
  func select(_ id: String?) {
    guard id == nil || installed.contains(where: { $0.id == id }) else { return }
    selectedID = id
    if let id {
      defaults.set(id, forKey: "appearance.mod")
    } else {
      defaults.removeObject(forKey: "appearance.mod")
    }
    AppearanceColors.set(active?.colors)
    notice = active.map { "\($0.name) is enabled." } ?? "Search’s standard appearance is active."
    for window in NSApp.windows {
      window.backgroundColor = Palette.NS.ground
      window.contentView?.needsDisplay = true
    }
  }
  func remove(_ id: String) throws {
    guard installed.contains(where: { $0.id == id }) else { return }
    try FileManager.default.removeItem(at: folder.appendingPathComponent(id + ".json"))
    if selectedID == id { select(nil) }
    reload()
    notice = "Appearance mod removed."
  }
  func chooseFile(in window: NSWindow?) {
    guard let window else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose an appearance-mod JSON file. It changes browser chrome only."
    panel.beginSheetModal(for: window) { [weak self] result in
      guard result == .OK, let url = panel.url else { return }
      do { try self?.install(url) } catch { self?.notice = error.localizedDescription }
    }
  }
}
