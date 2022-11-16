//
//  PasteAppDelegate.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Cocoa
import Carbon
import Preferences
import KeyboardShortcuts


class PasteAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var rMenu = {
        let menu = NSMenu(title: "Paste 设置")
        let item1 = NSMenuItem(title: "偏好设置", action: #selector(settingsAction), keyEquivalent: ",")
        menu.addItem(item1)
        menu.addItem(NSMenuItem.separator())
        let item3 = NSMenuItem(title: "退出Paste", action: #selector(NSApplication.shared.terminate), keyEquivalent: "q")
        menu.addItem(item3)
        return menu
    }()
    
    private lazy var mainWindow: PasteMainWindowController = {
        let mainWindow = PasteMainWindowController()
        return mainWindow
    }()
    var frontApp: NSRunningApplication?
    
    private lazy var settingsWindowController = { SettingsWindowController(
        preferencePanes: [PasteGeneralSettingsViewController(),
                          PasteShortcutsSettingViewController(),],
        style: .toolbarItems,
        animated: true
    )}()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setStatus()
        PasteBoard.main.startListening()
        setDefaultPrefs()
        KeyboardShortcuts.onKeyDown(for: .pasteKey) {
            var curFrame: NSRect?
            if let frame = NSScreen.main?.frame {
                curFrame = frame
            }
            self.showOrDismissWindow(curFrame)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        self.menuBarItem.isVisible = true
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}

extension PasteAppDelegate {
    func setDefaultPrefs() {
        let prefs = UserDefaults.standard
        if !prefs.bool(forKey: PrefKey.appAlreadyLaunched.rawValue) {
            LaunchAtLogin.isEnabled = true
            prefs.set(true, forKey: PrefKey.onStart.rawValue)
            prefs.set(true, forKey: PrefKey.pasteDirect.rawValue)
            prefs.set(HistoryTime.week.rawValue, forKey: PrefKey.historyTime.rawValue)
        }
    }
}

extension PasteAppDelegate {
    
    func setStatus() {
        menuBarItem.isVisible = true
        self.menuBarItem.button?.image = NSImage(named: "paste_icon_Normal")
        self.menuBarItem.button?.target = self
        self.menuBarItem.button?.action = #selector(statusBarClick)
        self.menuBarItem.button?.sendAction(on: [.leftMouseUp,.rightMouseUp])
    }
    
    @objc func statusBarClick(sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        let frame = sender.window?.screen?.frame
        if event.type == .leftMouseUp {
            showOrDismissWindow(frame)
        } else if event.type == .rightMouseUp {
            self.menuBarItem.popUpMenu(rMenu)
        }
    }
    
    @objc func settingsAction() {
        self.settingsWindowController.show()
    }
    
}

extension PasteAppDelegate {
    public func dismissWindow(completionHandler:(() -> Void)? = nil) {
        mainWindow.dismissWindow(completionHandler: completionHandler)
    }
    public func showOrDismissWindow(_ frame: NSRect? = nil) {

        if mainWindow.isVisable {
            mainWindow.dismissWindow()
        } else {
            frontApp = NSWorkspace.shared.frontmostApplication
            mainWindow.show(in:frame)
        }
    }
}

extension Settings.PaneIdentifier {
    static let general = Self("general")
    static let shortcuts = Self("shortcuts")
}
