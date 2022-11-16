//
//  PasteScrollView.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/7.
//

import Foundation
import Cocoa
protocol PasteScrollViewDelegate {
    func loadMoreData()
}
class PasteScrollView: NSScrollView {
    var delegate: PasteScrollViewDelegate?
    var isLoding = false
    var noMore = false
    override func scrollWheel(with event: NSEvent) {
        if event.subtype == .mouseEvent {
            if let cgEvent = event.cgEvent?.copy() {
                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: Double( event.scrollingDeltaY))
                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value:0.0)
                if let nEvent = NSEvent(cgEvent: cgEvent) {
                    super.scrollWheel(with: nEvent)
                } else {
                    super.scrollWheel(with: event)
                }
            } else {
                super.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    override func scroll(_ clipView: NSClipView, to point: NSPoint) {
        super.scroll(clipView, to: point)
        if noMore { return }
        print("scrollView scroll = \(point)")
        let width = NSScreen.main?.frame.width ?? 2000
        if point.x + width + 500 > clipView.documentRect.width {
            if !isLoding {
                isLoding = true
                delegate?.loadMoreData()
            }
        }
    }
    
}
