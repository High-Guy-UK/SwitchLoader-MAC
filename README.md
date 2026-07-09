# SwitchLoader

SwitchLoader is a native Swift macOS rewrite path for the practical parts of NS-USBloader.

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
- A SwiftUI workflow that can grow into Goldleaf USB and RCM support later.

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

USB install currently targets Awoo/Tinfoil-compatible installers. Goldleaf USB and RCM payload injection are planned next-stage work and need hardware testing.
