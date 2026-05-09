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
        super.init(window: window)
        window.contentViewController = hostingController
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show(category: SettingCategory? = nil) {
        Task { await PasteDataStore.main.updateStorageSize() }
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
    }
}
