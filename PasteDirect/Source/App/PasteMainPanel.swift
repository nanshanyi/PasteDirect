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
        // nonactivatingPanel: 面板可成为 key window 接收键盘输入(搜索/方向键/回车)，
        // 但不会让本 app 变成 active app，前台 app 不失活，正在进行的内联编辑不被打断。
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
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
