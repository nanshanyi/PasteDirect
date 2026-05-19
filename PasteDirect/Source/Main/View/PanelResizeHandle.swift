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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseY = NSEvent.mouseLocation.y
        initialHeight = window?.frame.height ?? 0
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = NSEvent.mouseLocation.y
        let totalDelta = currentY - initialMouseY
        let targetHeight = initialHeight + totalDelta
        onResize?(targetHeight)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnd?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}
