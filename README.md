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
- A Netflix-style Library view with one featured game panel, fanart/backdrop artwork, cover art, clickable/custom title artwork, media strip, file sizes, install-order actions, and quick game selection.
- IGDB metadata matching with IGDB status/fix buttons, cached results, trailer links, automatic Twitch token caching, and optional background ScreenScraper clearlogo enrichment when saved credentials already exist.
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

The Library tab enriches local install files with artwork and game details from IGDB. Add a Twitch Developer Client ID and Client Secret in the Metadata sheet; SwitchLoader fetches and caches the IGDB OAuth token automatically. ScreenScraper is no longer shown as a normal metadata provider in the UI; if valid ScreenScraper credentials already exist in the local settings file, SwitchLoader can quietly use it only to fill missing clear/logo artwork after an explicit metadata fetch.

Launch and the Library Refresh button now perform a quick local/cache scan only. Press **Fetch New Art** when you want SwitchLoader to call IGDB for newly discovered games. IGDB calls are rate-limited inside the app to 4 requests per second and no more than 8 open requests at once.

Each game can be matched against IGDB using the red/green IGDB pill in the game panel. A green tick means the game has a saved IGDB match; a red X means it still needs matching. SwitchLoader uses IGDB for displayed titles, fanart/backdrops, covers, screenshots, summaries, release details, genres, developers, publishers, database links, and trailer links.

Metadata lookups are cached under the user's Application Support folder. Normal launch and Refresh scans reuse that cache; the explicit **Fetch New Art** action only fetches missing IGDB entries. Provider credentials are stored in a local SwitchLoader settings file, not the macOS Keychain:

```text
~/Library/Application Support/SwitchLoader/MetadataProviders.json
```

Cached library metadata is stored separately:

```text
~/Library/Application Support/SwitchLoader/LibraryMetadataCache.json
```

Title/logo artwork in the featured Library panel is clickable. You can paste an image URL, choose a local image from the Mac, or clear the custom image later. Local custom artwork is copied into SwitchLoader's Application Support folder so it keeps working after reopening the app:

```text
~/Library/Application Support/SwitchLoader/CustomArtwork/
```

## Switch Receiver

The Switch-side receiver is only for the Homebrew workflow. It receives generated Homebrew folders from the Mac app and writes them to SD card paths such as `sdmc:/switch`, `sdmc:/atmosphere`, `sdmc:/bootloader`, `sdmc:/config`, and `sdmc:/themes`.

Commercial title installation remains the Awoo/Tinfoil-compatible workflow from the Mac app's Install tab.

## Current Scope

USB install currently targets Awoo/Tinfoil-compatible installers from the Install tab. The Library tab is a local library browser and queue builder for owned install files, with metadata/artwork enrichment from IGDB and optional background ScreenScraper clearlogo fill-in. The Homebrew workflow downloads public GitHub release assets, assembles selected apps into an SD card folder, and can send the generated folder over USB to SwitchLoader Receiver for direct placement under `sdmc:/switch`, `sdmc:/atmosphere`, and related homebrew paths. RCM payload injection is implemented from the CrystalRCM/fusee-style flow and has been tested with Hekate payload launching over USB.

## Attribution

RCM payload launching is derived from [CrystalRCM](https://github.com/prayerie/CrystalRCM), which is licensed under GPL-3.0. See `THIRD_PARTY_NOTICES.md`.
