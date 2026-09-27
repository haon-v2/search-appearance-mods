# Installing and updating the appearance loader

Search and its original app icon are by **Drice Roland / Office Commun and Search’s contributors**. Appearance support is a community contribution by **Noah Helms (@haon-v2)**. This is an unofficial preview, not an endorsed Search update. The original MIT notice remains in LICENSE.

## First install or upgrade from 0.3.x and older

1. Download **Search-Appearance-Mod-Loader-macOS-arm64.zip** from [the loader releases](https://github.com/haon-v2/search-appearance-mods/releases). Apple Silicon, macOS 14+.
2. Quit **Search Mod Preview**. Unzip and move **Search Mod Preview.app** into Applications, replacing the old preview if installed. Keep its name; do not replace the official **Search.app**.
3. Reopen the preview. Existing preview tabs, settings, profile and imported mods remain in its separate data folder. An app update does not delete that folder.
4. This app is ad-hoc signed and not notarized. If blocked, use System Settings → Privacy & Security → Open Anyway for this app.

**First switching from official Search requires logging into your websites again.** Official Search’s cookies, sign-ins and saved-password access are not migrated into this separate preview. Its original data stays in place. Drice / Office Commun would need to integrate the loader and release it under Search’s official signing identity to offer a normal Search update retaining those sign-ins. There is no upstream commitment or timeline.

The loader includes **no mods**. [Curve Tabs](https://github.com/haon-v2/curve-tabs) is a separate, optional package: Settings → Appearance → Import Mod… → Enable.

## Update from inside the app (0.4.0 and newer)

Open **Settings → About**, choose **Check now**, then **Download and Restart**. The Search menu’s **Check for Updates…** opens the same preview updater. Updates install only after your click. Save unfinished forms first; the normal quit path saves all windows and pending browser data, then the new app reopens your saved session.

The download can be cancelled before verification. If the connection, verification, or installation fails, About explains the error and offers a retry. A helper waits until the old app exits before replacing it. A failed replacement or launch request restores the old bundle; a successful new launch removes the backup. The updater does not migrate or clear profiles, mods, cookies, history or settings.

The app must be in a writable folder, preferably Applications. A read-only disk image, translocated copy, symlink, or folder owned by another account requires moving the app manually; the updater does not request administrator privileges. Backups are retained if recovery cannot complete. These protections cannot guarantee recovery from disk failure or a new app that crashes after macOS accepts its launch.

**One final manual installation is needed for 0.3.x and earlier.** Those releases only open the download page; they cannot install the new installer themselves. Install 0.4.0 using the steps above. Subsequent compatible signed releases can use Download and Restart.

Checks run about once a day while open and fetch public GitHub release metadata without an account or API key. No browsing history, profile or installed-mod list is sent; GitHub receives the request and IP address. Failed or unverifiable checks never claim the app is current. Intel builds are not offered ARM64 updates.

### How updates are verified

A dedicated Ed25519 public key is pinned in the loader. The publication job signs the exact `loader-update.json` bytes into `loader-update.sig`, after build and compatibility tests pass. The private signing key is a GitHub Actions secret available only to the publication job, which does not execute merged browser code. It is never shipped in the app or mod packages. The manifest binds the version, build, platform, repository download URL and archive SHA-256. The updater also verifies the extracted app’s bundle identity, version, CPU architecture and code integrity, and refuses downgrades. The helper repeats checks after quitting before it touches the installed app.

This is community-release authentication, **not Apple notarization or Office Commun’s Developer ID signature**. The original Search updater’s trust checks stay unchanged. First installation still uses the existing macOS approval flow. Protect the release-signing secret and workflow permissions. Losing the signing key requires a reviewed key transition or another manual installation; changing the repository’s public-key file alone does not update installed apps’ pinned key.

## How Search updates reach the loader

The `Search update compatibility` GitHub Actions workflow checks the latest **stable official release** every six hours and on demand. Unreleased main-branch changes and betas are not automatically shipped.

1. Merge the release into this fork, preserving upstream commit history and attribution. Only the fork’s introductory README gets an automatic documentation conflict resolution; upstream’s full README is retained separately.
2. Stop on code, workflow, license or other conflicts. No incompatible build is published.
3. Build an Apple Silicon preview, validate appearance packages and update manifests, and run the actual app in an isolated test profile. Tests cover the standard fallback, existing schema-1 edge-rail packages, page interaction, selection, closing, reordering around the corner, overflow, resizing, light/dark mode, folded reveal, sidebars on either side, folder operations across multiple windows, restoring folders and native groups after a restart, and installer authentication, downgrade rejection, rollback and helper relaunch.
4. Only after those checks pass, publish a separate preview release with its source, checksum, update manifest and detached Ed25519 signature. A draft is invisible to the app until all assets are uploaded. The publish job cannot execute the merged browser code and the build job has no repository write permission.
5. The preview offers that release on its next check; you can check immediately in Settings → About.

The mod package and loader remain separate. Schema-1 packages do not need to be reimported on ordinary host updates. If a future API is incompatible, a migration or new package version will be needed before it can ship.

**Compatibility is tested, not guaranteed for every future Search change.** The checks cover the loader’s supported paths, not every browser behavior, extension or website. A merge conflict, failed test, macOS/toolchain requirement, GitHub outage, or workflow failure can delay a release. The last working release remains available. Check the [workflow status](https://github.com/haon-v2/search-appearance-mods/actions/workflows/search-updates.yml) if Search has advanced but the preview hasn’t.

GitHub can disable scheduled workflows after 60 days without repository activity. A maintainer must re-enable the workflow if that happens. Failed integration needs a reviewed fix, then rerunning the workflow; a failed draft publication is retried on the next run. No automation changes the installed official Search app or contacts the original author.
