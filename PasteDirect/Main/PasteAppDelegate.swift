//
//  PasteAppDelegate.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Carbon
import Cocoa
import KeyboardShortcuts
import Preferences

class PasteAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var rMenu = NSMenu(title: "设置").then {
        let item1 = NSMenuItem(title: "偏好设置", action: #selector(settingsAction), keyEquivalent: ",")
        $0.addItem(item1)
        $0.addItem(NSMenuItem.separator())
        let item3 = NSMenuItem(title: "退出", action: #selector(NSApplication.shared.terminate), keyEquivalent: "q")
        $0.addItem(item3)
    }

    public lazy var mainWindowController = PasteMainWindowController()

    public var frontApp: NSRunningApplication?

    private lazy var settingsWindowController = SettingsWindowController(
        preferencePanes: [PasteGeneralSettingsViewController(),
                          PasteShortcutsSettingViewController()],
        style: .toolbarItems,
        animated: true
    )

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setStatusItem()
        PasteBoard.main.startListening()
        setDefaultPrefs()
        KeyboardShortcuts.onKeyDown(for: .pasteKey) {
            let curFrame = NSScreen.main?.frame
            self.showOrDismissWindow(curFrame)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension PasteAppDelegate {
    private func setDefaultPrefs() {
        let prefs = UserDefaults.standard
        if !prefs.bool(forKey: PrefKey.appAlreadyLaunched.rawValue) {
            LaunchAtLogin.isEnabled = true
            prefs.set(true, forKey: PrefKey.appAlreadyLaunched.rawValue)
            prefs.set(true, forKey: PrefKey.onStart.rawValue)
            prefs.set(true, forKey: PrefKey.pasteDirect.rawValue)
            prefs.set(HistoryTime.week.rawValue, forKey: PrefKey.historyTime.rawValue)
        }
    }
}

extension PasteAppDelegate {
    private func setStatusItem() {
        menuBarItem.isVisible = true
        menuBarItem.button?.image = NSImage(named: "paste_icon_Normal")
        menuBarItem.button?.target = self
        menuBarItem.button?.action = #selector(statusBarClick)
        // 使用leftMouseDown的话，会导致，新showwindow无法成为焦点
        menuBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusBarClick(sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        let frame = sender.window?.screen?.frame
        if event.type == .leftMouseUp {
            showOrDismissWindow(frame)
        } else if event.type == .rightMouseUp {
            menuBarItem.popUpMenu(rMenu)
        }
    }

    @objc private func settingsAction() {
        settingsWindowController.show()
    }
}

extension PasteAppDelegate {
    public func dismissWindow(completionHandler: (() -> Void)? = nil) {
        mainWindowController.dismissWindow(completionHandler: completionHandler)
    }

    public func showOrDismissWindow(_ frame: NSRect? = nil) {
        if mainWindowController.isVisable {
            mainWindowController.dismissWindow()
        } else {
            frontApp = NSWorkspace.shared.frontmostApplication
            mainWindowController.show(in: frame)
        }
    }
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let shortcuts = Self("shortcuts")
}
