# Draft: optional declarative appearance mods

Not posted. Prepared for discussion under Search’s contribution guidelines.

Could Search expose a small, optional appearance API for local packages? The aim is to change chrome colors and choose supported native tab layouts while keeping Search in charge of tabs, page lifetimes, navigation, and extensions.

A local prototype adds Settings → Appearance, disabled by default. Packages are bounded JSON manifests: identity, description, supported layout ID, and paired light/dark color roles. Import never enables a package automatically. Unsupported versions/layouts/fields and symlinks are refused. Disable/remove restores standard rendering, and a missing or corrupt selected package falls back to it. There are no scripts, network requests, package dependencies, or browsing-data permissions.

The host exposes a generic edge-rail renderer with bounded radius, tab-length and spacing settings. Curve Tabs is a separate JSON package with its own repository and release, configuring that renderer; it is not bundled with the loader. This deliberately does not promise arbitrary CSS or Swift injection: adding a new layout requires host support.

Would this fit Search’s direction? If so, the proposal can be split into the generic appearance API and an optional renderer. Preview-only app identity and packaging changes would not be included in an upstream PR.

Validation so far covers manifest rejection, persistence, import/enable/remove, palette selection, standard fallback, unchanged loaded webview identities, native click/drag/close/scroll, resizing, and light/dark rendering. Remaining work before an upstream contribution includes agreement on the API and completeness of alternate-renderer accessibility and tab/space interactions.
