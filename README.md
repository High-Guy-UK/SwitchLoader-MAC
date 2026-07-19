# SwitchLoader

SwitchLoader is a native Swift macOS app for Switch USB install workflows, local library browsing, metadata artwork matching, homebrew app pack building, and RCM payload launching.

The main workflow is USB install:

- Choose XCI, XCZ, NSP, NSZ, or a split folder.
- Set the device installer to wait for USB files.
- Connect the device over USB.
- Send the selected files from the Mac.

The app currently includes:

- Awoo/Tinfoil-compatible USB transfer.
- Split file creation.
- Split file merge.
- Library scanning for NSP, NSZ, XCI, XCZ, and split folders inside a chosen folder and its subfolders.
- A Netflix-style Library view with one featured game panel, fanart/backdrop artwork, cover art, clear/logo artwork, media strip, file sizes, install-order actions, and quick game selection.
- TheGamesDB and ScreenScraper metadata matching with separate per-provider match buttons, provider status pills, cached results, and combined best-available artwork/details.
- YouTube trailer playback from cached metadata trailer links.
- A Homebrew tab with a built-in GitHub starter catalog, custom repository entries, release asset downloads, ready-to-copy SD card folders, and USB install to SwitchLoader Receiver.
- RCM payload pushing for `.bin` payloads while the device is in RCM mode.
- A SwiftUI workflow with separate Install, Library, Homebrew, RCM, and Log tabs.

## Dependency

USB support uses Homebrew `libusb`:

```sh
brew install libusb
```

The checked-in Xcode project is configured for the default Apple Silicon Homebrew paths under `/opt/homebrew`.

## Run

```sh
swift run SwitchLoader
```

## Open in Xcode

Open `SwitchLoader.xcodeproj` and run the `SwitchLoader` scheme. The project contains:

- `SwitchLoader`, the macOS app target.
- `SwitchLoaderCore`, the reusable transfer/file framework target.
- `App/Assets.xcassets`, including the app icon.

## Test

```sh
swift test
```

## Library Metadata and Artwork

The Library tab can enrich local install files with artwork and game details from:

- TheGamesDB.
- ScreenScraper.

Each game can be matched separately against each provider using the red/green TGDB and ScreenScraper pills in the game panel. A green tick means that source has a saved match; a red X means that source still needs matching. SwitchLoader combines the best available data from both sources when rendering the game panel, so it can use fanart/backdrops, covers, clear/logo artwork, banners, screenshots, summaries, release details, genres, developers, publishers, and trailer links where available.

Metadata lookups are cached under the user's Application Support folder so refreshes only fetch missing or incomplete data. Provider credentials are stored in a local SwitchLoader settings file, not the macOS Keychain:

```text
~/Library/Application Support/SwitchLoader/MetadataProviders.json
```

Cached library metadata is stored separately:

```text
~/Library/Application Support/SwitchLoader/LibraryMetadataCache.json
```

## Switch Receiver

The Switch-side receiver is only for the Homebrew workflow. It receives generated Homebrew folders from the Mac app and writes them to SD card paths such as `sdmc:/switch`, `sdmc:/atmosphere`, `sdmc:/bootloader`, `sdmc:/config`, and `sdmc:/themes`.

Commercial title installation remains the Awoo/Tinfoil-compatible workflow from the Mac app's Install tab.

## Current Scope

USB install currently targets Awoo/Tinfoil-compatible installers from the Install tab. The Library tab is a local library browser and queue builder for owned install files, with metadata/artwork enrichment from TheGamesDB and ScreenScraper. The Homebrew workflow downloads public GitHub release assets, assembles selected apps into an SD card folder, and can send the generated folder over USB to SwitchLoader Receiver for direct placement under `sdmc:/switch`, `sdmc:/atmosphere`, and related homebrew paths. RCM payload injection is implemented from the CrystalRCM/fusee-style flow and has been tested with Hekate payload launching over USB.

## Attribution

RCM payload launching is derived from [CrystalRCM](https://github.com/prayerie/CrystalRCM), which is licensed under GPL-3.0. See `THIRD_PARTY_NOTICES.md`.
