//
//  PasteMainWindowController.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/20.
//

import Carbon
import Cocoa

final class PasteMainWindowController: NSWindowController {

    var isVisible: Bool { window?.isVisible ?? false }

    /// 记录目标 frame，动画用
    private var targetFrame: NSRect = .zero

    init() {
        let panel = PasteMainPanel(contentViewController: PasteMainViewController())
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Show / Dismiss

    func show(in screenFrame: NSRect?) {
        guard let window else { return }
        let screen = screenFrame ?? .zero
        let height = Layout.viewHeight

        // 目标位置：屏幕底部，四周留 screenPadding
        let inset = Layout.screenPadding
        targetFrame = NSRect(x: screen.origin.x + inset, y: screen.origin.y + inset, width: screen.width - inset * 2, height: height)

        // 起始位置：在屏幕下方（不可见）
        var startFrame = targetFrame
        startFrame.origin.y -= height
        window.setFrame(startFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(self.targetFrame, display: true)
        }
    }

    func dismissWindow(_ completionHandler: (() -> Void)? = nil) {
        guard let window, window.isVisible else {
            completionHandler?()
            return
        }

        // 向下滑出
        var endFrame = window.frame
        endFrame.origin.y -= endFrame.height

        Task {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().setFrame(endFrame, display: true)
            }
            self.window?.orderOut(nil)
            completionHandler?()
        }
    }
}

// MARK: - NSWindowDelegate

extension PasteMainWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        #if !DEBUG
        dismissWindow()
        #endif
    }
}
