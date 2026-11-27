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
        let controller = PasteMainViewController()
        let panel = PasteMainPanel(contentViewController: controller)
        // 窗口第一次显示时 AppKit 会把焦点交给第一个可编辑的视图（搜索框），viewDidAppear 随后又切回列表。
        // 搜索框拿焦点要初始化输入法、加载写作工具，白白占掉十来毫秒，直接从列表开始
        panel.initialFirstResponder = controller.initialFirstResponder
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

        // 面板位置：屏幕底部，四周留 screenPadding。窗口再往外扩出阴影边距，可以超出屏幕边缘
        let inset = Layout.screenPadding
        let panelFrame = NSRect(x: screen.origin.x + inset, y: screen.origin.y + inset, width: screen.width - inset * 2, height: height)
        targetFrame = panelFrame.insetBy(dx: -Layout.panelShadowMargin, dy: -Layout.panelShadowMargin)

        // 起始位置：在屏幕下方（不可见）
        var startFrame = targetFrame
        startFrame.origin.y -= targetFrame.height
        window.setFrame(startFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        // 先把第一帧画完、提交给渲染服务再开始滑入：第一次打开时这一帧要建全部卡片的图层，
        // 留到动画开始后才做，动画的前几帧就被吞掉，面板看起来是跳出来的
        window.displayIfNeeded()
        CATransaction.flush()

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
