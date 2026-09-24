# Appearance Mod Loader for Search

**Search is created by [Drice Roland (@driceroland)](https://github.com/driceroland) / [Office Commun](https://officecommun.com), with its upstream contributors. Full credit for the original browser belongs to them.**

This community fork adds **appearance-mod support by Noah Helms ([@haon-v2](https://github.com/haon-v2))**. It is an experimental contribution built on [Search](https://github.com/driceroland/Search), not an official or endorsed Search release. The original MIT license and copyright notice are preserved in [LICENSE](LICENSE).

## Loader and mods are separate

This repository contains the **host/loader**, not a collection of bundled mods. A fresh installation has no mods installed and uses Search’s standard appearance.

- **Loader:** imports, validates, enables, disables, and removes local appearance packages. Includes generic native rendering capabilities and light/dark color roles.
- **Mods:** separate JSON packages distributed independently. [Curve Tabs](https://github.com/haon-v2/curve-tabs) is an optional example with its own repository and release. It is not required or bundled with the loader.

The host keeps Search’s WebKit engine, page lifecycle, and browsing features. Mods describe supported appearance settings; they cannot execute scripts or native code or read browsing data. Version 1 supports standard tabs and a configurable top/right edge rail. The edge rail is a generic host renderer; a mod supplies its radius, tab length, spacing, and optional palette. Arbitrary new rendering behavior still requires a host update.

## Try the loader

> **First-time setup: expect to log in to all your websites again.** Search Mod Preview uses a separate profile and does not automatically carry over Search’s cookies, active sign-ins, or saved-password access. Your existing Search data and sign-ins remain in the original app. This applies when first switching to the preview; updating an existing preview installation retains its own profile.

Download **Search-Appearance-Mod-Loader-macOS-arm64.zip** from [Releases](https://github.com/haon-v2/search-appearance-mods/releases). The app is called **Search Mod Preview**, retains Search’s original app icon, and keeps its profile separate from installed Search and Curve. Apple Silicon, macOS 14+. Locally signed, not notarized.

1. Unzip and move **Search Mod Preview.app** to Applications, keeping its name.
2. Open it; if macOS blocks this local build, use System Settings → Privacy & Security → Open Anyway for this app.
3. Download a mod separately.
4. Open **Settings → Appearance → Import Mod…**, choose the mod’s JSON file, then **Enable**.

Disable or remove mods in the same page. Installing the loader alone changes no tab layout. An unmodified official Search app cannot load these packages yet.

[Full installation and API guide](docs/APPEARANCE-MODS.md) · [Credits](CREDITS.md) · [Original Search README](README-UPSTREAM.md)

## Build and test

```sh
bash build-mod-preview.sh
python3 Tests/run_appearance_tests.py
```

The output is `build/Search Mod Preview.app`. Use the preview script, not upstream’s publishing/reset scripts. Swift 6 toolchain and macOS 14+ required. See the guide for isolated native integration tests.

This preview is based on upstream commit `9e31d6ba636f4cad8504c209e07870fa2b68b8ca`. Upstream’s contribution guidelines request a design discussion before substantial changes; no upstream issue or PR has been submitted. Publishing this community fork does not imply acceptance into Search.
