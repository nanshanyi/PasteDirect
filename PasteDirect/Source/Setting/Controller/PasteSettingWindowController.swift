//
//  PasteSettingWindowController.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Cocoa
import SwiftUI

class PasteSettingWindowController: NSWindowController {
    private let hostingController = NSHostingController(rootView: SettingsView()).then {
        $0.sizingOptions = [.preferredContentSize]
    }
    
    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        window.contentViewController = hostingController
        super.init(window: window)
        // 提前触发布局
        hostingController.view.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        showWindow(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func show() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        showWindow(self)
        window?.center()
    }
}
