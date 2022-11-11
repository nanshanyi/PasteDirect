//
//  PasteAppDelegate.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Cocoa
import Carbon


class PasteAppDelegate: NSObject, NSApplicationDelegate {
    let menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var rMenu = {
        let menu = NSMenu(title: "Paste 设置")
        let item1 = NSMenuItem(title: "偏好设置", action: #selector(settingsAction), keyEquivalent: ",")
        menu.addItem(item1)
        let item2 = NSMenuItem(title: "退出Paste", action: #selector(NSApplication.shared.terminate), keyEquivalent: "Q")
        menu.addItem(item2)
        return menu
    }()
    
    private lazy var mainWindow: PasteMainWindowController = {
        let mainWindow = PasteMainWindowController()
        return mainWindow
    }()
    let hotKey = KeyCombo(modifierFlags:[.command, .shift], keyCode: UInt16(kVK_ANSI_V))
    var frontApp: NSRunningApplication?
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        setStatus()
        PasteBoard.main.startListening()
        HotKey.shared.delegate = { [self] k in
            switch k {
            case .keyPress(let key):
                if key == hotKey {
                    var curFrame: NSRect?
                    if let frame = NSScreen.main?.frame {
                        curFrame = frame
                    }
                    showOrDismissWindow(curFrame)
                }
            }
        }
        
        try? HotKey.shared.watch(hotKey)
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
    
    func setStatus() {
        menuBarItem.isVisible = true
        self.menuBarItem.button?.image = NSImage(named: "paste_icon_Normal")
        self.menuBarItem.button?.target = self
        self.menuBarItem.button?.action = #selector(statusBarClick)
        self.menuBarItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }
    
    @objc func statusBarClick(sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        let frame = sender.window?.screen?.frame
        if event.type == .leftMouseDown {
            showOrDismissWindow(frame)
        } else if event.type == .rightMouseDown {
            self.menuBarItem.popUpMenu(rMenu)
        }
    }
    
    @objc func settingsAction() {
        
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
