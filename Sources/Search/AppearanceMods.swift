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
        "Local layouts and colors for the browser. They cannot read websites, browsing data, or passwords, and contain no executable code."
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
            Button(mods.selectedID == mod.id ? "Disable" : "Enable") {
              if mods.selectedID == mod.id {
                mods.select(nil)
              } else {
                mods.select(mod.id)
                if mod.tabLayout == .edgeRail {
                  browser.prefs.sidebar = false
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
          if mods.selectedID == mod.id && mod.tabLayout == .edgeRail && browser.prefs.sidebar {
            Button("Show Mod Layout") {
              browser.prefs.sidebar = false
              browser.folded = false
            }
          }
        }.padding(12).background(Palette.wash, in: RoundedRectangle(cornerRadius: 10))
      }
      Text(mods.notice).font(.system(size: 12)).foregroundStyle(Palette.muted).accessibilityLabel(
        mods.notice)
      Text(
        "Version 1 supports standard tabs and configurable edge rails, plus light/dark color pairs. New layout types require an update to the host app. These are not WebExtensions or Zen Mods."
      ).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }.foregroundStyle(Palette.ink)
  }
}
