# Changelog

[简体中文](CHANGELOG.md) | English

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [3.6.0] - 2026-08-31

### Added
- In-app automatic updates powered by [Sparkle](https://sparkle-project.org/): new versions can be downloaded and installed right inside the app with an automatic relaunch — no more manually downloading the dmg and dragging it into Applications.
- New "Automatically download updates" toggle: updates found will be downloaded silently in the background and installed when the app quits.
- New GitHub Actions release workflow: pushing a `v*` tag automatically builds, signs, packages the dmg, generates the appcast, and publishes the Release (see `docs/RELEASE.md`).

### Changed
- Update checking moved from a hand-rolled GitHub API checker to Sparkle's standard update UI, with skip-this-version support and localized update prompts; the v3.5.x "check on launch" and "ignored version" settings migrate automatically.

## [3.5.0] - 2026-07-31

### Added
- Pin clipboard items: pin frequently used items from the right-click menu. Pinned items always stay at the top of the list and are exempt from history expiration cleanup.
- The "Always paste as plain text" toggle now works: when enabled, pasted text has its formatting stripped.

### Changed
- Tidied up storage locations: the database, images, and ignore list have moved from the sandbox Documents folder to the more semantically correct Application Support (migrated automatically in-app, no manual steps needed).
- Smoother image preview loading: decoding of large originals moved to a background thread.
- The right-click menu is now rebuilt each time it opens, so "Paste to X" always shows the correct target after switching the frontmost app.

### Fixed
- Fixed identical content being recorded again after a restart, with old entries that couldn't be deleted (now uses a stable content hash for deduplication).
- Fixed built-in password apps (e.g. Passwords, Keychain Access) losing their ignore protection after the second launch.
- Fixed search keywords containing `%` or `_` being treated as wildcards and matching unrelated content.
- Fixed image text recognition (OCR) not retrying within the same session after an occasional failure.

## [3.4.0] - 2026-06-22

### Added
- Live Text support in image preview: select and copy text directly from images while previewing, just like the system "Live Text" in Photos; phone numbers, URLs, and more are tappable. Complements image OCR — OCR makes in-image text searchable, while Live Text lets you grab text on the fly while viewing.

### Changed
- Much smaller image storage: copied images (especially screenshots, Preview, Finder, and other sources that only offer uncompressed TIFF) are now losslessly re-encoded to PNG before being saved, typically shrinking disk usage by an order of magnitude.
- Image preview now scales to the original aspect ratio exactly, matching the system preview — no more stretching or letterboxing; preview images also get rounded corners.
- Increased the preview panel's maximum size, while it now shrinks automatically to fit the current screen's visible area and the main panel height, so large images are clearer without going off-screen.
- The storage size shown in Settings now includes the externally stored original image files, reflecting actual disk usage.
- Reworked image storage to slim down the database: original images are now stored as standalone files while the database keeps only thumbnails, loading originals on demand. Database size, memory usage, and list load times all improved, and copying large images no longer slows down the history list. Deleting an image also removes its original file, and disk space is reclaimed automatically after expired-item cleanup.
- Tuned the preview panel height and the minimum display size for small images, so small images are no longer shrunk too much and the overall panel is more compact.

## [3.3.0] - 2026-06-05

### Added
- Image OCR text recognition and search:
  - Text in copied images is recognized automatically (on-device via Vision, Chinese + English, offline).
  - Search matches text inside images, so image content is searchable too.
  - New "Copy Text" and "Paste Text to Frontmost App" entries in the image context menu.
  - New "Automatically recognize text in images" toggle in Settings (on by default).

### Changed
- Showing the panel no longer interrupts your current work: it no longer steals focus from the frontmost app, in-progress inline editing is preserved, and you can paste directly.
- Smoother paste experience: on double-click/Enter paste, the close animation now plays fully before writing to the clipboard, removing the abrupt "no animation, list jumps instantly" feel.

## [3.2.0] - 2026-05-19

### Added
- Panel height is now resizable by dragging the top edge, with elastic bounce-back when released out of range.
- Panel height is saved automatically and restored on next launch.
- New "Panel" section in Settings with an option to reset the panel height.

### Changed
- Panel content scales dynamically with height; compact layout kicks in automatically for small panels.
- Improved tag alignment in normal mode.

## [3.1.3] - 2026-05-10

### Added
- In-app update check, with automatic update checks and the option to skip the current version.

### Fixed
- Fixed the Settings window not being centered on first open.

### Changed
- Improved permission configuration.

## [3.1.2] - 2026-05-08

### Added
- Brand-new custom search bar with inline filter tags.
- Guidance prompt shown when there is no history or no search results.

### Changed
- Dark mode support.
- When the search bar is focused, Esc now closes the filter popover first.
- Refined top padding on the Settings page.

## [3.1.0-beta] - 2026-04-29

### Fixed
- Swift 6 concurrency compatibility fixes.
- Fixed known issues.

### Changed
- Code quality improvements.
- Documentation updates.

## [3.0.0] - 2026-04-20

### Added
- Clipboard content preview.
- Multi-language localization support.

### Changed
- Rewrote the popup logic for smoother interaction.
- Refactored the code architecture for better overall performance.

## [2.4.0] - 2026-04-09

### Added
- New multi-dimensional filter panel: filter by type (text/image/color), source app, and time range in combination.
- The search bar shows the active filters as tags.

### Changed
- Database queries now support predicate pushdown, filtering at the SQL layer to reduce memory overhead.
- Color extraction results are cached to avoid repeated parsing.
- Reworked pagination; state management consolidated into a single source of truth in DataStore.

### Fixed
- Fixed records being skipped due to pagination offset drift after deleting data.
- Fixed redundant database scans caused by in-memory filtering during color-filter pagination.
- Fixed pagination requests potentially interrupting search before first-screen data returned.
- Fixed the inability to continue loading after a load failure.

## [2.3.1] - 2026-02-03

### Added
- Quick paste.

## [2.3.0] - 2026-01-29

### Added
- Hex color support.

### Changed
- Added self-signing to avoid re-granting Accessibility permission after every update.

## [2.1.1] - 2025-12-11

### Fixed
- Scroll back to the start position when new clipboard content is added.

### Changed
- Unified the status bar icon with the app icon; added a list selection animation.

## [2.1.0] - 2025-10-09

### Changed
- Maintenance and improvements.

## [2.0.1] - 2025-09-29

### Added
- Brand-new app icon.

### Changed
- Full adaptation to the new macOS 26 UI.

## [2.0.0] - 2025-09-28

### Changed
- Full adaptation to the new macOS 26 UI.

## [1.5.0] - 2024-12-27

### Added
- TIFF format support.

> ⚠️ This release changed the database schema. Users on older versions should uninstall and reinstall, or clear data before installing over the top.

## [1.4.6] - 2024-10-31

### Added
- Quickly delete a selected item with the Backspace key.

## [1.4.5] - 2024-08-30

### Fixed
- Fixed an HTML type display issue.
- Fixed the launch-at-login toggle being inverted.

### Changed
- Added do-catch error handling; code cleanup.

## [1.4.3] - 2024-08-22

### Fixed
- Various bug fixes.

## [1.4.2] - 2024-08-09

### Fixed
- Fixed an error when pasting directly with Enter.

## [1.4.1] - 2024-07-30

### Fixed
- Filter out whitespace characters.

## [1.4.0] - 2024-07-24

### Changed
- Maintenance and version updates.

## [1.3.1] - 2024-07-15

### Changed
- Code cleanup.

[Unreleased]: https://github.com/nanshanyi/PasteDirect/compare/v3.4.0...HEAD
[3.4.0]: https://github.com/nanshanyi/PasteDirect/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/nanshanyi/PasteDirect/compare/v3.2.0...v3.3.0
[3.2.0]: https://github.com/nanshanyi/PasteDirect/compare/v3.1.3...v3.2.0
[3.1.3]: https://github.com/nanshanyi/PasteDirect/compare/v3.1.2...v3.1.3
[3.1.2]: https://github.com/nanshanyi/PasteDirect/compare/v3.1.0-beta...v3.1.2
[3.1.0-beta]: https://github.com/nanshanyi/PasteDirect/compare/v3.0.0...v3.1.0-beta
[3.0.0]: https://github.com/nanshanyi/PasteDirect/compare/v2.4.0...v3.0.0
[2.4.0]: https://github.com/nanshanyi/PasteDirect/compare/v2.3.1...v2.4.0
[2.3.1]: https://github.com/nanshanyi/PasteDirect/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/nanshanyi/PasteDirect/compare/v2.1.1...v2.3.0
[2.1.1]: https://github.com/nanshanyi/PasteDirect/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/nanshanyi/PasteDirect/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/nanshanyi/PasteDirect/compare/v2.0...v2.0.1
[2.0.0]: https://github.com/nanshanyi/PasteDirect/compare/v1.5.0...v2.0
[1.5.0]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.6...v1.5.0
[1.4.6]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.5...v1.4.6
[1.4.5]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.3...v1.4.5
[1.4.3]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.2...v1.4.3
[1.4.2]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/nanshanyi/PasteDirect/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/nanshanyi/PasteDirect/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/nanshanyi/PasteDirect/compare/v1.3...v1.3.1
