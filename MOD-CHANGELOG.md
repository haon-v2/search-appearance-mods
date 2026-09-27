# Appearance loader changes

Search itself is by Drice Roland / Office Commun and its contributors. Its unchanged changelog is in CHANGELOG.md.

## 0.4.0

- Add Download and Restart for compatible preview updates, with progress and cancellation while downloading.
- Authenticate manifests with a pinned Ed25519 key; verify archives and app identity/code integrity before replacement. Sign release manifests in the isolated publication job.
- Wait for a normal quit, preserve the preview profile and mods, retain the old app for rollback, and reopen the updated app. Refuse read-only/translocated targets and downgrades.
- Route the Search menu’s update action to the preview updater.
- Older previews require one manual installation of 0.4.0 to gain in-app installation.

## 0.3.1

- Integrate Search v1.0.4, including multiple windows, native tab groups, right-side sidebar, shortcuts, import improvements, and upstream security fixes.
- Adapt curved-rail spacing and folded reveal for sidebars on either side.
- Preserve Curve folder membership through Search's new session decoder and window records. Share folder definitions between windows and handle moving/removing folders safely.
- Keep the preview updater running from Search's new shared startup path, using the community release feed rather than the official signed updater.
- Include Search's read-only AppleScript dictionary and updated icon generation; show the upstream What's New card for the integrated browser version.
- Add native multi-window, right-sidebar and group/session restart regression checks.

## 0.3.0

- Independent sidebar-folder modules, compatible with Curve Tabs. Curve Tab Folders is distributed separately.
- Folder creation, renaming, collapse, drag-to-folder, Curve JSON import/export and per-space persistence.

## 0.2.1

- Optional “Show sidebar with curved tabs” switch in Appearance settings. Enabling a rail mod preserves the existing sidebar choice.
- Keep the resizable sidebar and curved rail visible together; page and search-field spacing account for both. Navigation buttons stay in the sidebar in this layout.
- Folding hides both and reveals them from the left, top or right edge. The same tabs and page instances remain shared between layouts.

## 0.2.0

- Merge Search v1.0.3, including upstream security fixes and bookmarks bar.
- A dedicated preview update channel checks compatible loader releases, with explicit errors and a download link. Official Search updates cannot remove the loader.
- Scheduled upstream release integration, with build, validation and native UI checks before publishing. Conflicts or failed checks stop publication.
- Keep schema 1 packages compatible, Search’s original icon, separate preview profile and separately distributed mods.

## 0.1.1

Package Search’s original icon explicitly, replacing the obsolete Curve icon.

## 0.1.0

Import, validate, enable, disable and remove local declarative appearance packages. Standard tabs and a configurable top/right edge rail; no executable mod code and no bundled mods.
