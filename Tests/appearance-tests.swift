import AppKit
import Foundation
let testRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOD_TEST_ROOT"]!)
enum Store { static func quarantine(_ file: URL) { try? FileManager.default.moveItem(at:file,to:file.appendingPathExtension("corrupt")) }; static func file(_ name: String) -> URL { testRoot.appendingPathComponent(name) }; static let settings = UserDefaults(suiteName: "local.search.mods.unit-tests")! }
enum Palette { enum NS { static let ground = NSColor.windowBackgroundColor } }
let app = NSApplication.shared
func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
func rejects(_ object: [String: Any]) { do { _ = try AppearanceMod.decode(JSONSerialization.data(withJSONObject: object)); fatalError("Accepted invalid manifest") } catch {} }
MainActor.assumeIsolated {
 do {
    let defaults = Store.settings; defaults.removePersistentDomain(forName: "local.search.mods.unit-tests")
    let sample = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = try Data(contentsOf: sample), mod = try AppearanceMod.decode(data)
    check(mod.id == "test.rail" && mod.tabLayout == .edgeRail, "Rail manifest failed")
    var json = try JSONSerialization.jsonObject(with: data) as! [String:Any]
    for (key,value) in [("id","../escape" as Any),("schemaVersion",2),("tabLayout","javascript"),("script","alert(1)"),("name",String(repeating:"x",count:81))] { var invalid=json; invalid[key]=value; rejects(invalid) }
    json["colors"] = ["light":["ground":"red"],"dark":[:]];rejects(json)
    json["colors"] = ["light":["website":"#ffffff"],"dark":[:]];rejects(json)
    do { _=try AppearanceMod.decode(Data(repeating:32,count:65_537));fatalError("Oversize accepted") } catch {}
    for radius in [-1, 0, 121] { var bad = json; bad.removeValue(forKey: "colors"); bad["rail"] = ["cornerRadius": radius, "tabLength": 210, "gap": 12]; rejects(bad) }
    let store=AppearanceMods(folder:testRoot.appendingPathComponent("mods"),defaults:defaults)
    check(store.installed.isEmpty && store.selectedID == nil,"Fresh loader shipped with a mod")
    try store.install(sample);check(!store.usesEdgeRail,"Import automatically enabled code")
    do { try store.install(sample);fatalError("Duplicate overwrote mod") } catch {}
    store.select("test.rail");check(store.usesEdgeRail,"Enable failed")
    let folderJSON: [String:Any] = ["schemaVersion":2,"id":"curve.tab-folders","name":"Curve Tab Folders","author":"Noah Helms","summary":"Sidebar tab folders","tabLayout":"standard","sidebarFolders":true]
    let folderFile = testRoot.appendingPathComponent("folder-module.json")
    try JSONSerialization.data(withJSONObject:folderJSON).write(to:folderFile)
    try store.install(folderFile); store.select("curve.tab-folders")
    check(store.usesEdgeRail && store.usesSidebarFolders, "Folder module replaced rail")
    let both = AppearanceMods(folder:testRoot.appendingPathComponent("mods"),defaults:defaults)
    check(both.usesEdgeRail && both.usesSidebarFolders,"Independent selection did not persist")
    both.select(nil); check(!both.usesEdgeRail && both.usesSidebarFolders,"Standard appearance disabled folders")
    both.disable("curve.tab-folders"); check(!both.usesSidebarFolders,"Folder disable failed")
    both.select("curve.tab-folders"); try both.remove("curve.tab-folders")
    check(!both.usesSidebarFolders,"Folder removal failed")
    for (key,value) in [("schemaVersion",1 as Any),("sidebarFolders",false),("script","evil")] {
        var invalid = folderJSON; invalid[key] = value; rejects(invalid)
    }
    let folderStore = TabFolderStore(file:testRoot.appendingPathComponent("folders.json"))
    let space = UUID(), other = UUID()
    let group = try folderStore.create("  Research  ",in:space)
    check(folderStore.folders(in:space).first?.name == "Research", "Name normalization")
    check(folderStore.valid(group,in:other) == nil,"Folder leaked into another space")
    do { _ = try folderStore.create("  ",in:space); fatalError("Empty name") } catch {}
    try folderStore.rename(group,to:"Reading");try folderStore.collapse(group,true)
    let saved = TabFolderStore(file:folderStore.file)
    check(saved.items == folderStore.items && saved.items[0].collapsed,"Folder persistence")
    try saved.remove(group);check(saved.items.isEmpty,"Folder deletion")
    print("PASS: independent folder module, schema boundaries, scoped folder CRUD and persistence")
    store.select("test.rail")
    let restored=AppearanceMods(folder:testRoot.appendingPathComponent("mods"),defaults:defaults);check(restored.usesEdgeRail,"Selection did not persist")
    restored.select(nil);check(!restored.usesEdgeRail,"Disable failed")
    json["id"]="test.colors";json["tabLayout"]="standard";json.removeValue(forKey:"rail");json["colors"]=["light":["ground":"#123456"],"dark":["ground":"#654321"]]
    let colorFile=testRoot.appendingPathComponent("colors.json");try JSONSerialization.data(withJSONObject:json).write(to:colorFile)
    try restored.install(colorFile);restored.select("test.colors")
    check(abs(AppearanceColors.color(role:"ground",dark:false)!.redComponent - 18.0/255)<0.001,"Light palette failed")
    check(abs(AppearanceColors.color(role:"ground",dark:true)!.redComponent - 101.0/255)<0.001,"Dark palette failed")
    try restored.remove("test.colors");check(restored.selectedID == nil && AppearanceColors.color(role:"ground",dark:false) == nil,"Remove did not reset palette")
    restored.select("test.rail")
    try Data("{}".utf8).write(to:testRoot.appendingPathComponent("mods/test.rail.json"))
    restored.reload();check(!restored.usesEdgeRail && restored.selectedID == nil,"Broken mod did not safely fall back")
    print("PASS: schema, bounds, executable/unknown-field rejection, import, duplicates, enable/disable, persistence, light/dark colors, removal and corrupted-mod fallback")
    defaults.removePersistentDomain(forName:"local.search.mods.unit-tests")
 } catch { fatalError(error.localizedDescription) }
}
