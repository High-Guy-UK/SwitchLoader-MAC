# SwitchLoader

SwitchLoader is a native Swift macOS app for Nintendo Switch workflows.

It is intended as a multi-use companion tool, including a local game library, metadata and artwork management, queue building, file utilities, and RCM payload injection.

## Highlights

- Native macOS app built with SwiftUI.
- Local game library with IGDB metadata, fanart, cover art, title artwork, trailers, file sizes, and quick game selection.
- Custom title artwork overrides from image URLs or local Mac files.
- Split and merge tools for large local files.
- RCM payload selection, connection status, and payload injection.
- Activity log for transfer, metadata, library, and RCM events.

## Dependency

Device communication uses `libusb`:

```sh
brew install libusb
```

The checked-in Xcode project is configured for the standard Apple Silicon `brew` layout.

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

The Library tab enriches local files with artwork and game details from IGDB. Add a Twitch Developer Client ID and Client Secret in the Metadata sheet; SwitchLoader fetches and caches the IGDB OAuth token automatically.

Launch and Library Refresh perform a quick local/cache scan only. Press **Fetch New Art** when you want SwitchLoader to call IGDB for newly discovered games. IGDB calls are rate-limited inside the app to 4 requests per second and no more than 8 open requests at once.

Each game can be matched against IGDB using the red/green IGDB pill in the game panel. A green tick means the game has a saved IGDB match; a red X means it still needs matching.

Metadata provider credentials are stored in a local SwitchLoader settings file:

```text
~/Library/Application Support/SwitchLoader/MetadataProviders.json
```

Cached library metadata is stored separately:

```text
~/Library/Application Support/SwitchLoader/LibraryMetadataCache.json
```

Custom title artwork is copied into SwitchLoader's Application Support folder so it keeps working after reopening the app:

```text
~/Library/Application Support/SwitchLoader/CustomArtwork/
```

## Current Scope

SwitchLoader currently focuses on local game library management, metadata/artwork enrichment, file preparation utilities, companion-device workflows, and RCM injection.

## Attribution

RCM payload launching is derived from [CrystalRCM](https://github.com/prayerie/CrystalRCM), which is licensed under GPL-3.0. See `THIRD_PARTY_NOTICES.md`.
