//
//  PasteMainWindow.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Cocoa

final class PasteMainPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        self.contentViewController = contentViewController
        level = .statusBar
        hasShadow = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
    }
}
