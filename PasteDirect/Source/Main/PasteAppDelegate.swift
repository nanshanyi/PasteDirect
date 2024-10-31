//
//  PasteAppDelegate.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import ApplicationServices
import Carbon
import Cocoa
import KeyboardShortcuts
import Settings

final class PasteAppDelegate: NSObject {
    private let menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var rMenu = NSMenu(title: "设置").then {
        let item1 = NSMenuItem(title: "偏好设置", action: #selector(settingsAction), keyEquivalent: ",")
        $0.addItem(item1)
        $0.addItem(NSMenuItem.separator())
        let item3 = NSMenuItem(title: "退出", action: #selector(NSApplication.shared.terminate), keyEquivalent: "q")
        $0.addItem(item3)
    }

    private lazy var mainWindowController = PasteMainWindowController()

    var frontApp: NSRunningApplication?

    private lazy var settingsWindowController = SettingsWindowController(
        panes: [PasteGeneralSettingsViewController(),
                PasteShortcutsSettingViewController(),
                PasteIgnoreListController()],
        style: .toolbarItems,
        animated: true
    )
}

// MARK: - NSApplicationDelegate

extension PasteAppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        initPaste()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

// MARK: - 私有方法

extension PasteAppDelegate {
    private func initPaste() {
        /// 设置状态栏
        setStatusItem()
        /// 开启剪贴板监听
        PasteBoard.main.startListening()
        /// 初始化DataStore
        PasteDataStore.main.setup()
        /// 记录是否第一次启动 设置开机自启
        if !PasteUserDefaults.appAlreadyLaunched {
#if !DEBUG
            LaunchAtLogin.isEnabled = true
#endif
            PasteUserDefaults.appAlreadyLaunched = true
            settingsAction()
        }
        
#if !DEBUG
        /// 检查辅助功能权限
        showPromptAccessibility()
#endif
        
        /// 注册快捷键
        KeyboardShortcuts.onKeyDown(for: .pasteKey) { [self] in
            let curFrame = NSScreen.main?.frame
            showOrDismissWindow(curFrame)
        }
    }

    private func showPromptAccessibility() {
        if !readPrivileges(prompt: false) {
            acquirePrivileges()
        }
    }
    
    private func acquirePrivileges(firstAsk: Bool = false) {
        if !self.readPrivileges(prompt: true), !firstAsk {
            let alert = NSAlert()
            alert.messageText = "PasteDirect 需要获取辅助功能权限"
            alert.informativeText = "点击确定跳转到系统设置页，如果列表中已存在PasteDirect，请删除后重新添加，并打开权限开关"
            alert.addButton(withTitle: "确定")
            alert.runModal()
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    private func readPrivileges(prompt: Bool) -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: prompt]
        let status = AXIsProcessTrustedWithOptions(options)
        Log(String(format: "Reading Accessibility privileges - Current access status %{public}@", String(status)))
        return status
    }

    private func setStatusItem() {
        menuBarItem.isVisible = true
        menuBarItem.button?.image = NSImage(named: "paste_icon_Normal")
        menuBarItem.button?.target = self
        menuBarItem.button?.action = #selector(statusBarClick)
        // 使用leftMouseDown的话，会导致，新showwindow无法成为焦点
        menuBarItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc
    private func statusBarClick(sender: NSStatusBarButton) {
        guard let event = NSApplication.shared.currentEvent else { return }
        let frame = sender.window?.screen?.frame
        if event.type == .leftMouseUp {
            showOrDismissWindow(frame)
        } else if event.type == .rightMouseUp {
            menuBarItem.popUpMenu(rMenu)
        }
    }

    @objc
    private func settingsAction() {
        settingsWindowController.show()
    }
}

// MARK: - 对外方法

extension PasteAppDelegate {
    func dismissWindow(_ completionHandler: (() -> Void)? = nil) {
        mainWindowController.dismissWindow(completionHandler)
    }

    func showOrDismissWindow(_ frame: NSRect? = nil) {
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
    static let ignore = Self("ignore")
}
