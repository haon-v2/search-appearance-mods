# Installing and updating the appearance loader

Search and its original app icon are by **Drice Roland / Office Commun and Search’s contributors**. Appearance support is a community contribution by **Noah Helms (@haon-v2)**. This is an unofficial preview, not an endorsed Search update. The original MIT notice remains in LICENSE.

## Install or upgrade

1. Download **Search-Appearance-Mod-Loader-macOS-arm64.zip** from [the loader releases](https://github.com/haon-v2/search-appearance-mods/releases). Apple Silicon, macOS 14+.
2. Quit **Search Mod Preview**. Unzip and move **Search Mod Preview.app** into Applications, replacing the old preview if installed. Keep its name; do not replace the official **Search.app**.
3. Reopen the preview. Existing preview tabs, settings, profile and imported mods remain in its separate data folder. An app update does not delete that folder.
4. This app is ad-hoc signed and not notarized. If blocked, use System Settings → Privacy & Security → Open Anyway for this app.

**First switching from official Search requires logging into your websites again.** Official Search’s cookies, sign-ins and saved-password access are not migrated into this separate preview. Its original data stays in place. Drice / Office Commun would need to integrate the loader and release it under Search’s official signing identity to offer a normal Search update retaining those sign-ins. There is no upstream commitment or timeline.

The loader includes **no mods**. [Curve Tabs](https://github.com/haon-v2/curve-tabs) is a separate, optional package: Settings → Appearance → Import Mod… → Enable.

## Why the old preview didn’t update

Versions 0.1.0 and 0.1.1 intentionally disabled the official updater: replacing the preview with official Search would remove the loader and cross app identities. **Install 0.2.0 or newer manually once.** The old app cannot acquire its new updater itself.

Starting with 0.2.0, Settings → About checks the community loader channel, and checks also run about once a day while the app is open. This fetches public release metadata from GitHub without an account or API key. It sends no browsing history, profile or installed-mod list; GitHub receives the ordinary network request and IP address. Failed checks say they failed instead of claiming the app is current.

A new version opens its release page through **Download update**. Follow the replacement instructions above. **Silent installation is not provided:** these community builds lack Office Commun’s Developer ID identity, and the original updater’s signature verification has not been weakened. SHA256SUMS.txt is published alongside each archive. Intel builds made locally are not offered the ARM64 download.

## How Search updates reach the loader

The `Search update compatibility` GitHub Actions workflow checks the latest **stable official release** every six hours and on demand. Unreleased main-branch changes and betas are not automatically shipped.

1. Merge the release into this fork, preserving upstream commit history and attribution. Only the fork’s introductory README gets an automatic documentation conflict resolution; upstream’s full README is retained separately.
2. Stop on code, workflow, license or other conflicts. No incompatible build is published.
3. Build an Apple Silicon preview, validate appearance packages and update manifests, and run the actual app in an isolated test profile. Tests cover the standard fallback, existing schema-1 edge-rail packages, page interaction, selection, closing, reordering around the corner, overflow, resizing, light/dark mode, folded reveal, sidebars on either side, folder operations across multiple windows, and restoring folders and native groups after a restart.
4. Only after those checks pass, publish a separate preview release with its source, checksum and update manifest. A draft is invisible to the app until all assets are uploaded. The publish job cannot execute the merged browser code and the build job has no repository write permission.
5. The preview offers that release on its next check; you can check immediately in Settings → About.

The mod package and loader remain separate. Schema-1 packages do not need to be reimported on ordinary host updates. If a future API is incompatible, a migration or new package version will be needed before it can ship.

**Compatibility is tested, not guaranteed for every future Search change.** The checks cover the loader’s supported paths, not every browser behavior, extension or website. A merge conflict, failed test, macOS/toolchain requirement, GitHub outage, or workflow failure can delay a release. The last working release remains available. Check the [workflow status](https://github.com/haon-v2/search-appearance-mods/actions/workflows/search-updates.yml) if Search has advanced but the preview hasn’t.

GitHub can disable scheduled workflows after 60 days without repository activity. A maintainer must re-enable the workflow if that happens. Failed integration needs a reviewed fix, then rerunning the workflow; a failed draft publication is retried on the next run. No automation changes the installed official Search app or contacts the original author.
