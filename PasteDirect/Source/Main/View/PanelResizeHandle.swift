//
//  PanelResizeHandle.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit

final class PanelResizeHandle: NSView {

    var onResize: ((_ targetHeight: CGFloat) -> Void)?
    var onResizeEnd: (() -> Void)?
    /// 鼠标悬停或拖动中,用于高亮把手
    var onActiveChange: ((Bool) -> Void)?

    private var isHovering = false { didSet { stateChanged() } }
    private var isDragging = false { didSet { stateChanged() } }

    private func stateChanged() {
        let active = isHovering || isDragging
        onActiveChange?(active)
        updateCursor(active)
    }

    /// 面板是 nonactivatingPanel,本 app 不会成为 active app,
    /// 而 cursor rect 和 cursorUpdate 只对 active app 生效,所以光标要在进出/拖动时手动设置。
    private func updateCursor(_ active: Bool) {
        (active ? NSCursor.resizeUpDown : NSCursor.arrow).set()
    }

    private var initialMouseY: CGFloat = 0
    private var initialHeight: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 只创建一次:.inVisibleRect 会自动跟随视图大小。
    /// 若每次布局都删掉重建,鼠标在区域内时会收到一次多余的 mouseExited,
    /// 把手悬停时的放大动画会触发布局,于是光标刚变成上下箭头就被改回普通箭头。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: .zero,
            // .cursorUpdate:面板是 key window 时,AppKit 每次鼠标移动都会做一次光标更新,
            // 区域内没有接管的话会回落成普通箭头,把我们刚设的上下箭头盖掉
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    // mouseMoved 只在鼠标位于跟踪区域内时送达,收到即说明在把手上:
    // 补上可能漏掉的进入状态,并重新设一次光标(防止被其他视图改回箭头)
    override func mouseMoved(with event: NSEvent) {
        if !isHovering { isHovering = true }
        NSCursor.resizeUpDown.set()
    }

    // 非激活面板上首次点击也要能直接开始拖动
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        initialMouseY = NSEvent.mouseLocation.y
        initialHeight = window?.frame.height ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        // 拖动时鼠标可能离开把手区域,光标保持上下箭头
        NSCursor.resizeUpDown.set()
        let currentY = NSEvent.mouseLocation.y
        let totalDelta = currentY - initialMouseY
        let targetHeight = initialHeight + totalDelta
        onResize?(targetHeight)
    }

    override func mouseUp(with event: NSEvent) {
        // 松手时按鼠标实际位置决定光标:仍在把手上保持上下箭头,否则恢复箭头
        isHovering = bounds.contains(convert(event.locationInWindow, from: nil))
        isDragging = false
        onResizeEnd?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

