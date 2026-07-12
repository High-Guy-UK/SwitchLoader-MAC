# Changelog

## Unreleased

### Added

- Native Swift package structure with a macOS SwiftUI app target.
- Reusable `SwitchLoaderCore` library target for transfer and file utilities.
- Awoo/Tinfoil network install core with file-list handshake generation and HTTP byte-range serving.
- Split and merge service for Switch-compatible `00`, `01`, `02` chunk folders with output size validation.
- SwiftUI macOS interface for file selection, network settings, transfer progress, split/merge actions, and logs.
- Xcode project file for native app development in Xcode.
- Custom macOS app icon asset catalog with generated SwitchLoader artwork.
- Native libusb-backed USB connection layer for installer/homebrew mode devices.
- Awoo/Tinfoil-compatible USB install flow for sending selected files on request.
- Smaller USB-first workflow interface for choosing files, setting the device waiting, connecting USB, and sending from the Mac.
- Compact install queue rows that show title and path on one line.
- Dedicated log tab in the main app header.
- Library tab for scanning a chosen folder and subfolders for NSP, NSZ, XCI, XCZ, and split folders.
- Library folder persistence, refresh, open-folder, add-all, and single-item add actions.
- Library folder parsing that shows the game folder name with Main Game, Update, DLC, or Other pills.
- Library row hover and right-click actions for full filename/path, Finder reveal, path copy, and queue add.
- Xcode app bundles now embed and re-link `libusb`, so the app can launch outside Xcode.
- RCM payload tab for choosing a `.bin` payload, guiding the device into RCM, and pushing over USB from the Mac.
- CrystalRCM/fusee-style RCM launcher core with embedded intermezzo stage, device ID read, payload chunk upload, and trigger step.
- Third-party attribution notice for the CrystalRCM-derived RCM implementation.
- RCM payload folder persistence so the payload picker reopens in the last used folder after restarting the app.
- Live RCM connection marker that turns green when a Switch in RCM mode is detected and keeps Push disabled until it is connected.

### Tests

- RCM payload layout and oversized payload coverage in `SwitchLoaderCoreTests`.
