//
//  PasteSettingWindowController.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Cocoa
import SwiftUI

class PasteSettingWindowController: NSWindowController {
    private let settingsViewModel = SettingsNavigationModel()

    private lazy var hostingController = NSHostingController(
        rootView: SettingsView(navigationModel: settingsViewModel)
    ).then {
        $0.sizingOptions = [.preferredContentSize]
    }

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        // 设置窗口之前开在别的桌面时，再打开要挪到当前桌面，而不是留在原处看不见
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.init(window: window)
        window.contentViewController = hostingController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(category: SettingCategory? = nil) {
        Task { await PasteDataStore.main.updateStorageSize() }
        if let category {
            settingsViewModel.selectedCategory = category
        }
        let isFirstShow = window?.isVisible == false
        if isFirstShow {
            hostingController.view.layoutSubtreeIfNeeded()
            let fitted = hostingController.sizeThatFits(in: NSSize(width: 600, height: 500))
            window?.setContentSize(fitted)
            window?.center()
        }
        showWindow(self)
        // macOS 14 起激活只是请求，前台 app 没让出焦点时系统可能不理会；
        // 本 app 没有 Dock 图标，激活没成功时 showWindow 不会把窗口提到其他 app 的窗口上面。
        // 先不论激活与否把窗口放到最前，再请求激活让它成为 key window
        window?.orderFrontRegardless()
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
