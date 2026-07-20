# Changelog

## 1.2.2

### Added

- Expanded native Nintendo Switch companion source tree.
- IGDB-backed Library metadata with cached OAuth tokens and rate-limited requests.
- Netflix-style Library featured panel with fanart, cover art, title artwork, trailers, file sizes, and quick game selection.
- Clickable title artwork controls for custom image URLs or local Mac images.
- Enlarged media viewer with arrow navigation.
- Wider/taller default app window with a restored bottom media artwork strip.
- RCM payload workflow with connection status and payload launch diagnostics.

### Changed

- Public docs now describe SwitchLoader as a multi-use Nintendo Switch tool focused on game library management, metadata/artwork, file utilities, companion workflows, and RCM injection.
- Metadata credentials are stored in a local Application Support settings file instead of the macOS Keychain.
- Library refresh uses cached/local data unless the user explicitly fetches new artwork.

### Fixed

- Added a missing C++ `<memory>` include required by the expanded native companion source.
- Improved local custom artwork persistence and rendering in the Library panel.

## 1.2.1

- Native macOS app packaging with bundled `libusb`.
- Library metadata/artwork caching and game grouping.
- RCM payload injection support.
- Swift package and Xcode project support.
