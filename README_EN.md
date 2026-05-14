<p align="center">
  <img width="128" height="128" alt="PasteDirect" src="https://github.com/user-attachments/assets/9873c83e-8839-4a49-86a4-aaf9c8439f07" />
</p>

<h1 align="center">PasteDirect</h1>

<p align="center">
  <a href="README_CN.md">简体中文</a> | English
</p>

<p align="center">
  A lightweight, secure, fully local clipboard history manager for macOS
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/version-3.1.3-green" alt="Version 3.1.3">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

## Features

- 🔒 **Fully local** — All data is stored in a local SQLite database, with zero network requests for better privacy
- 📋 **Multiple formats** — Records text, images, HTML, RTF, rich text, and code snippets
- 🎨 **Color detection** — Automatically detects Hex color values from the clipboard and displays visual previews
- ⌨️ **Global shortcut** — Default shortcut is `⌘⇧V`; custom shortcuts are supported
- 🔍 **Fast search** — Type keywords to instantly filter clipboard history; the search field uses a pill-style design
- 🏷️ **Multi-dimensional filters** — Combine filters by type (text/image/color), source app, and time range; active filters are shown as tags
- 👁️ **Space preview** — Press Space to quickly preview the selected item, including text, images, and color details
- 🖱️ **Multiple paste methods** — Paste by double-clicking, pressing Enter, or dragging an item to the target location
- 📝 **Plain text mode** — Remove rich-text formatting with one click and paste as plain text
- 🧹 **Auto cleanup** — Configure retention duration: 1 day / 1 week / 1 month / forever
- 🚫 **App filtering** — Ignore clipboard content from specific apps, such as Keychain or password managers
- 🪟 **macOS 26 ready** — Full support for the Liquid Glass visual effect

<img width="2704" height="958" alt="2026_04_27_10_40_37" src="https://github.com/user-attachments/assets/27c5215e-8603-4f63-8413-42eb5f08329d" />
<img width="2706" height="1404" alt="2026_04_27_10_41_07" src="https://github.com/user-attachments/assets/1cf3e03c-c9c5-442b-b909-ac82c2773ccc" />
<img width="2704" height="1514" alt="2026_04_27_10_41_27" src="https://github.com/user-attachments/assets/ef2999b6-c240-4c3a-94a4-1849e1c5b42d" />

## Installation

### Download

Download the latest `.dmg` file from [Releases](https://github.com/nanshanyi/PasteDirect/releases), open it, and drag `PasteDirect.app` into the `/Applications` folder.

### First launch

Because the app uses a self-signed certificate, macOS requires manual authorization on the first launch:

1. Right-click `PasteDirect.app` and choose **Open**
2. Click **Open** in the dialog that appears

Or use Terminal:

```bash
xattr -cr /Applications/PasteDirect.app
open /Applications/PasteDirect.app
```

After the first launch, macOS will ask you to grant **Accessibility** permission. This is required for clipboard monitoring and simulated paste operations.

<img width="530" height="494" alt="image" src="https://github.com/user-attachments/assets/cf00f162-b4ff-4ddc-8c7c-974d5bc2caca" />

If macOS shows a security warning for the self-signed certificate, go to **System Settings → Privacy & Security** and choose **Open Anyway**.

### Smooth updates

Starting from v2.2.0, PasteDirect uses a self-signed certificate mechanism so Accessibility permission is preserved during updates and does not need to be granted again.

Starting from v3.1.3, the app supports manually checking for updates in-app. You can also enable automatic update checks on launch in Settings.

## Usage

| Action | Description |
|------|------|
| `⌘⇧V` | Show / hide the clipboard panel (customizable) |
| Double-click | Paste the selected item |
| `Enter` | Paste the selected item |
| `Space` | Preview the selected item |
| `Delete` | Delete the selected item |
| `Esc` | Close preview / filter popover / clear search and filters / close panel in sequence |
| Drag | Drag an item to the target location to paste directly |
| Type text | Search and filter history; `Backspace` removes filters one by one |

<p align="center">
  <img width="629" alt="PasteDirect Settings" src="https://github.com/user-attachments/assets/a315da78-25d5-4382-8d93-4d827ec14a62" />
</p>

## Settings

- **Launch at login** — Run automatically when you log in
- **Menu bar icon** — Show / hide the menu bar icon
- **Direct paste** — Automatically paste the selected item into the current app
- **Plain text paste** — Remove formatting and paste plain text only
- **History retention** — 1 day / 1 week / 1 month / forever
- **Ignored apps** — Configure apps whose clipboard content should not be recorded
- **Shortcut** — Customize the global shortcut for opening the panel
- **Check for updates** — Supports manual update checks and checking automatically on launch

## Build from source

### Requirements

- macOS 13.0+
- Xcode 16+
- Swift 6

### Build steps

```bash
git clone https://github.com/nanshanyi/PasteDirect.git
cd PasteDirect
open PasteDirect.xcodeproj
```

Select the `PasteDirect` scheme in Xcode and click Run. Dependencies are fetched automatically through Swift Package Manager.

### Dependencies

| Library | Purpose |
|----|------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global shortcuts |
| [SQLite.swift](https://github.com/nicklama/SQLite.swift) | Local database |
| [SnapKit](https://github.com/SnapKit/SnapKit) | Auto Layout |

## License

MIT License
