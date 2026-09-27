import SwiftUI

struct AppearanceTabChrome: View {
  @ObservedObject var browser: Browser
  @ObservedObject private var mods = AppearanceMods.shared
  var overlay = false
  var body: some View {
    if mods.usesEdgeRail, let rail = mods.active?.rail {
      EdgeRailChrome(browser: browser, configuration: rail, overlay: overlay)
    } else {
      TabBar(browser: browser)
        .background {
          if overlay { Palette.ground.shadow(color: .black.opacity(0.14), radius: 20, y: 4) }
        }
    }
  }
}

struct AppearanceModsPage: View {
  @ObservedObject var browser: Browser
  @ObservedObject private var mods = AppearanceMods.shared
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Appearance mods").font(.headline)
      Text(
        "Local layouts and optional built-in sidebar features. Mod files contain no executable code and cannot access websites or passwords. Folder data stays on this Mac."
      ).font(.system(size: 12)).foregroundStyle(Palette.muted)
      HStack {
        Button("Import Mod…") { mods.chooseFile(in: Links.window) }
        Spacer()
        Button("Use Standard Appearance") { mods.select(nil) }.disabled(mods.selectedID == nil)
      }
      ForEach(mods.installed) { mod in
        VStack(alignment: .leading, spacing: 7) {
          HStack {
            Text(mod.name).fontWeight(.medium)
            Spacer()
            Button(mods.isEnabled(mod.id) ? "Disable" : "Enable") {
              if mods.isEnabled(mod.id) {
                mods.disable(mod.id)
              } else {
                mods.select(mod.id)
                if mod.isFolderModule { browser.prefs.sidebar = true }
                if mod.tabLayout == .edgeRail {
                  browser.folded = false
                  browser.peeking = false
                }
              }
            }
            Button("Remove") {
              do { try mods.remove(mod.id) } catch { mods.notice = error.localizedDescription }
            }
          }
          Text(mod.summary).font(.system(size: 12)).foregroundStyle(Palette.muted)
          Text("By \(mod.author) · API \(mod.schemaVersion)").font(.system(size: 11))
            .foregroundStyle(Palette.muted)
          if mods.selectedID == mod.id && mod.tabLayout == .edgeRail {
            Toggle("Show sidebar with curved tabs", isOn: Binding(
              get: { browser.prefs.sidebar },
              set: { show in
                withAnimation(Motion.glide) {
                  browser.prefs.sidebar = show
                  browser.folded = false
                  browser.peeking = false
                }
              }
            ))
            .toggleStyle(.switch)
            Text("Keep the resizable sidebar beside the curved rail, or turn it off for more page space.")
              .font(.system(size: 11)).foregroundStyle(Palette.muted)
          }
        }.padding(12).background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
      }
      Text(mods.notice).font(.system(size: 12)).foregroundStyle(Palette.muted).accessibilityLabel(
        mods.notice)
      Text(
        "Version 1 supports layouts and colors. Version 2 adds independent sidebar-folder modules, which can run alongside a layout mod. New layout types require an update to the host app. These are not WebExtensions or Zen Mods."
      ).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }.foregroundStyle(Palette.ink)
  }
}
