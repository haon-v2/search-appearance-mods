# Appearance Mod Loader — experimental API 1

Search is by **Drice Roland / Office Commun and its contributors**. Appearance-mod support is contributed by **Noah Helms (@haon-v2)**. This unofficial preview preserves Search’s MIT license and is based on `9e31d6ba636f4cad8504c209e07870fa2b68b8ca`.

## Separate host and packages

The loader ships no mods. Its native rendering capabilities are generic: standard tabs, a configurable top/right edge rail, and light/dark color roles. Mods are separate JSON documents that choose and configure those capabilities. Curve Tabs is maintained separately at https://github.com/haon-v2/curve-tabs and is never installed automatically.

This is a declarative appearance API, not a loader for arbitrary JavaScript, CSS, Swift binaries, WebExtensions, or Zen Mods. New rendering capabilities require a host update. A mod cannot read sites, passwords, or browsing data, execute code, or download other files.

## Install

> **First-time setup: expect to log in to all your websites again.** Search Mod Preview uses a separate profile and does not automatically carry over Search’s cookies, active sign-ins, or saved-password access. Your existing Search data and sign-ins remain in the original app. This applies when first switching to the preview; updating an existing preview installation retains its own profile.

1. Download and unzip **Search-Appearance-Mod-Loader-macOS-arm64.zip** from the loader’s GitHub release. Requires Apple Silicon and macOS 14+. Intel users must build locally.
2. Move **Search Mod Preview.app** to Applications under that name, keeping your existing Search.
3. Open it. This preview is ad-hoc signed, not notarized. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway for this app.
4. Download your chosen mod separately. In **Settings → Appearance**, select **Import Mod…**, choose its JSON file, then **Enable**.

Import never enables a package automatically. Disable returns to the standard appearance without closing pages. Remove uninstalls the package. Missing or corrupt selected files fall back to standard rendering. Up to 32 packages may be installed; one is active at a time. A layout mod may select horizontal tabs; the sidebar remains available through Search’s controls.

Your unmodified installed Search cannot import packages until it includes loader support. The preview is the modified host, not an extension installed into Search.app.

## Isolation

- Bundle ID: `local.noah.search.mod-preview`.
- App data: `~/Library/Application Support/Search Mod Preview/`.
- Keychain label: `Search Mod Preview`.
- Mod folder: `AppearanceMods` inside that app data folder.
- Cookies and settings use the preview identity; no automatic Search/Curve migration.
- The upstream automatic updater is disabled in the preview.

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
