//
//  PasteSettingWindowController.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Cocoa
import SwiftUI

class PasteSettingWindowController: NSWindowController {
    private let splitViewController = SettingSplitViewController()
    private let hostingController = NSHostingController(rootView: SettingsView())
    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.minSize = NSSize(width: 600, height: 500)
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .automatic
        super.init(window: window)
        window.contentViewController = hostingController
        window.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        hostingController.view.layoutSubtreeIfNeeded()
        showWindow(self)
        window?.center()
    }
}
