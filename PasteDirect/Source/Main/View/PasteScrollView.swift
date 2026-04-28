//
//  PasteScrollView.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/7.
//

import Cocoa
import Foundation

@MainActor
protocol PasteScrollViewDelegate: NSObjectProtocol {
    func loadMoreData()
}

final class PasteScrollView: NSScrollView {
    weak var delegate: PasteScrollViewDelegate?
    var canLoadMore = true

    override var hasVerticalScroller: Bool {
        get { false }
        set { /* ignore */ }
    }
    override var hasHorizontalScroller: Bool {
        get { false }
        set { /* ignore */ }
    }

    override func scrollWheel(with event: NSEvent) {
        if let cgEvent = event.cgEvent?.copy(), event.scrollingDeltaX == 0 {
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: Double(event.scrollingDeltaY))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0.0)
            if let nEvent = NSEvent(cgEvent: cgEvent) {
                super.scrollWheel(with: nEvent)
            } else {
                super.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func scroll(_ clipView: NSClipView, to point: NSPoint) {
        super.scroll(clipView, to: point)
        guard canLoadMore else { return }
        let visibleWidth = documentVisibleRect.width
        if point.x + visibleWidth * 2 > clipView.documentRect.width {
            canLoadMore = false
            delegate?.loadMoreData()
        }
    }
}
