# Appearance Mod Loader — experimental APIs 1 and 2

Search is by **Drice Roland / Office Commun and its contributors**. Appearance-mod support is contributed by **Noah Helms (@haon-v2)**. This unofficial preview preserves Search’s MIT license and records its integrated stable Search release in `UPSTREAM_VERSION` and its exact commit in `UPSTREAM_COMMIT`.

## Separate host and packages

The loader ships no mods. Its native rendering capabilities are generic: standard tabs, a configurable top/right edge rail, and light/dark color roles. API 2 additionally supports an independent native sidebar-folder capability. Mods are separate JSON documents that choose and configure those capabilities. Curve Tabs is maintained separately at https://github.com/haon-v2/curve-tabs and is never installed automatically.

This is a declarative appearance API, not a loader for arbitrary JavaScript, CSS, Swift binaries, WebExtensions, or Zen Mods. New rendering capabilities require a host update. A mod cannot read sites, passwords, or browsing data, execute code, or download other files.

## Install

> **First-time setup: expect to log in to all your websites again.** Search Mod Preview uses a separate profile and does not automatically carry over Search’s cookies, active sign-ins, or saved-password access. Your existing Search data and sign-ins remain in the original app. This applies when first switching to the preview; updating an existing preview installation retains its own profile.

> **A seamless update requires official integration.** To add appearance mods to your existing Search installation while retaining its profile and sign-ins through a normal update, Drice / Office Commun would need to accept and integrate the loader into Search and ship it as an official signed update. This community preview cannot deliver that official update. The feature has not been integrated upstream, and there is no commitment or timeline from Drice.

1. Download and unzip **Search-Appearance-Mod-Loader-macOS-arm64.zip** from the loader’s GitHub release. Requires Apple Silicon and macOS 14+. Intel users must build locally.
2. Move **Search Mod Preview.app** to Applications under that name, keeping your existing Search.
3. Open it. This preview is ad-hoc signed, not notarized. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway for this app.
4. Download your chosen mod separately. In **Settings → Appearance**, select **Import Mod…**, choose its JSON file, then **Enable**.

Import never enables a package automatically. Disable returns to the standard appearance without closing pages. Remove uninstalls the package. Missing or corrupt selected files fall back to standard rendering. Up to 32 packages may be installed; one appearance layout and one independent sidebar-folder module can be active at the same time. With an edge-rail mod enabled, **Show sidebar with curved tabs** in Appearance lets you keep the resizable sidebar beside the rail or use the rail alone. The choice is saved and also follows View → Show Tabs in Sidebar (⇧⌘S). Enabling a mod preserves your current sidebar choice.

Your unmodified installed Search cannot import packages until it includes loader support. The preview is the modified host, not an extension installed into Search.app.

## Isolation

- Bundle ID: `local.noah.search.mod-preview`.
- App data: `~/Library/Application Support/Search Mod Preview/`.
- Keychain label: `Search Mod Preview`.
- Mod folder: `AppearanceMods` inside that app data folder.
- Cookies and settings use the preview identity; no automatic Search/Curve migration.
- Official Search’s signed updater cannot replace the preview. The preview checks compatible loader releases through GitHub daily and in Settings → About; installation is manual. See [Updating](UPDATING.md).

Quit and trash the preview app to remove the host. No default-browser registration or personal-profile migration is performed by these instructions.

## Write a color mod

```json
{
  "schemaVersion": 1,
  "id": "example.paper",
  "name": "Paper",
  "author": "Your name",
  "summary": "A warm frame with standard tabs.",
  "tabLayout": "standard",
  "colors": {
    "light": { "ground": "#FAF7F0", "wash": "#E8E1D5" },
    "dark": { "ground": "#211F1B", "wash": "#38332A" }
  }
}
```

Supported roles: `ground`, `ink`, `muted`, `faint`, `hairline`, `wash`, `hover`. Omitted roles inherit Search’s palette. Supply both light and dark dictionaries if colors are included. Values are `#RRGGBB`.

## Configure an edge rail

Use `"tabLayout": "edgeRail"` and a `rail` object with `cornerRadius` (40–120), `tabLength` (120–300), and `gap` (4–24), in points. All three fields are required. These settings are rejected for a standard layout. The generic renderer follows the top and right edges; this API does not yet describe arbitrary paths or other edge combinations.

Packages have a lowercase letter followed by up to 63 lowercase letters, digits, dots, or hyphens as their ID; name and author are at most 80 characters, summary at most 300, file at most 64 KB. Unknown fields, unsupported versions/layouts, invalid colors and rail bounds, and symlinks are rejected. Duplicate IDs cannot overwrite an installed package silently.

## Build and verify

```sh
bash build-mod-preview.sh
python3 Tests/run_appearance_tests.py
```

Requires macOS 14+, Swift 6, and Python 3. The app output is `build/Search Mod Preview.app`. WebExtensions retain Search’s macOS 15.4+ requirement. Do not use upstream’s publish, reset, or install scripts for this preview.

For native integration tests, enable the bench and skip welcome only in a test profile:

```sh
defaults write local.noah.search.mod-preview.test.loaderrelease bench -bool true
defaults write local.noah.search.mod-preview.test.loaderrelease welcomed -bool true
SEARCH_PROBE=loaderrelease 'build/Search Mod Preview.app/Contents/MacOS/SearchModPreview'
```

In a second terminal:

```sh
APPEARANCE_TEST_WORLD=loaderrelease python3 Tests/run_appearance_ui_tests.py
```

The fixture under `Tests/fixtures` is test data only, never bundled or installed. To verify an independent package, set `APPEARANCE_TEST_MOD` to its JSON path. Tests use local pages and confirm loaded webview identity survives mod switches, plus click/drag/close/scroll, resize, and hidden-rail reveal.

## Limitations

This is an experimental first release. Alternate-rail accessibility is not yet complete. Search’s inline tab-edit/site-information card and space-switching gestures remain in its standard layout, not the edge rail. Common tab actions and keyboard navigation are supported. The rail observes metadata without creating additional webviews and scrolls with a short-lived timer; these checks do not establish a browser-wide memory ceiling or resolve the previously reported Curve memory incident.

No upstream issue or PR has been submitted. See `UPSTREAM-PROPOSAL.md` for a discussion draft. Preview-specific identity changes should be kept separate from a proposed upstream integration.

## Sidebar folder modules (API 2, loader 0.3.0+)

[Curve Tab Folders](https://github.com/haon-v2/curve-tab-folders) is distributed separately from both this loader and Curve Tabs. Import its JSON package and Enable it in Appearance. Enabling it opens the sidebar without replacing the selected layout.

```json
{"schemaVersion":2,"id":"example.folders","name":"Tab Folders","author":"Your name","summary":"Sidebar folder organization","tabLayout":"standard","sidebarFolders":true}
```

API 2 currently accepts only the independent folder capability: `sidebarFolders` must be true, `tabLayout` must be standard, and colors/rail must be absent. API 1 cannot request this capability. Package files are still data-only and cannot execute code. The host stores and manages folder data on the user’s behalf.

The folder-plus menu beside Open Tabs creates, imports, and exports folders. Right-click a tab to move it, or drag it onto a folder header; drop onto Open Tabs to move it out. Folder names are bold, disclosures are on the right, and dotted theme-colored guides appear only on child-tab hover. Remove Folder keeps its tabs open. Private tabs cannot enter saved folders or exports.

Folders belong to the current Search space. Native session entries preserve membership; `tab-folders.json` holds names and collapse states. Disabling/removing the module hides the grouping without deleting it. Use Standard Appearance changes only the layout. With Curve Tabs enabled, the curved rail follows the active tab’s folder.

Imports use the original Curve JSON array of `{name,tabs:[{title,url}]}` records, bounded to 1 MB, 64 folders and 100 tabs. Additional bookmark fields from Curve are ignored. Only HTTP(S) URLs without embedded credentials are accepted, and duplicate URLs inside matching folder names are skipped. Imports restore sleeping tabs without allocating new WebViews. Exports include only folders in the current space, excluding private and test tabs.

`python3 Scripts/test_native.py` now includes folder checks and a real preview restart. Folder source modules: TabFolderStore.swift, TabFolderActions.swift, TabFolderSidebar.swift.
