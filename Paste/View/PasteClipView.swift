//
//  PasteClipView.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/11.
//

import Cocoa

class PasteClipView: NSClipView {
    
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        let constrained = super.constrainBoundsRect(proposedBounds)
//        CGFloat scrollValue = proposedBounds.origin.y;
        print("\(proposedBounds.debugDescription)")
        return constrained
    }
    
    override func scroll(_ point: NSPoint) {
        super.scroll(point)
        print("scroll =\(point)")
    }
}
