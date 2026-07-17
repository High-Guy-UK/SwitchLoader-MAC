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
- Corrected the RCM upload endpoint for libusb so payload writes use endpoint `0x01` instead of the IOKit pipe index.
- RCM launch diagnostics now log the discovered bulk endpoints, prepared payload size, chunk count, and trigger length.
- Matched the RCM payload wrapper padding to the fusee-launcher/CrystalRCM reference layout.
- RCM launch confirmation now treats the successful trigger handoff as success instead of failing when macOS still reports an RCM device.
- Successful RCM launches no longer show the expected post-launch disconnect as a warning.
- Xcode archive builds now target Apple Silicon so the bundled Homebrew libusb library links during Product > Archive.
- Corrected the largest app icon size to the macOS archive-required 1024px asset.
- README and app version metadata now reflect the RCM-capable `v1.1.0` release.
- Library now groups install files into game cards, stores the library folder as a security-scoped bookmark, fetches TGDB artwork/details, and shows a rich game detail sheet with install-order queue actions.
- Library metadata lookups now cache successful matches, missed matches, and failed attempts so TGDB is only called for newly discovered games.
- Library games now display as a rounded cover-poster carousel with horizontal scrolling, vertical wheel support, and a clean grey scrollbar.
- TGDB library metadata now filters for Nintendo Switch platform matches only, preventing other console covers from being cached or displayed.
- Game detail popups are larger and richer, with extra TGDB details, media, local file sections, English metadata hints, and manual matching for unmatched games.
- Library carousel posters are slightly smaller and the visible scrollbar has been removed for a cleaner shelf layout.
- Homebrew tab with a 50-entry GitHub starter catalog, saved HomebrewApps archive folder, ready/downloaded indicators, multi-select downloads, custom GitHub repo entries, and generated ready-to-copy homebrew folders.
- SwitchLoader Receiver native `.nro` for installing generated Homebrew folders over USB into SD card homebrew paths.
- Homebrew tab **Install to Switch** action for sending generated folders to SwitchLoader Receiver.
- Launch splash screen for the macOS app with animated SwitchLoader handheld artwork.

### Tests

- RCM payload layout and oversized payload coverage in `SwitchLoaderCoreTests`.
- Hekate-sized payload chunk count coverage for the reference RCM wrapper layout.
