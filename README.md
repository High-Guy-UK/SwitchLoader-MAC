# SwitchLoader

SwitchLoader is a native Swift macOS app for Switch USB install workflows, local library browsing, homebrew app pack building, and RCM payload launching.

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

## Current Scope

USB install currently targets Awoo/Tinfoil-compatible installers from the Install tab. The Homebrew workflow downloads public GitHub release assets, assembles selected apps into an SD card folder, and can send the generated folder over USB to SwitchLoader Receiver for direct placement under `sdmc:/switch`, `sdmc:/atmosphere`, and related homebrew paths. RCM payload injection is implemented from the CrystalRCM/fusee-style flow and has been tested with Hekate payload launching over USB.

## Attribution

RCM payload launching is derived from [CrystalRCM](https://github.com/prayerie/CrystalRCM), which is licensed under GPL-3.0. See `THIRD_PARTY_NOTICES.md`.
