//
//  NSLabel.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/8/23.
//

import AppKit

class NSlabel: NSTextField {
    init() {
        super.init(frame: .zero)
        initLabel()
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        initLabel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initLabel() {
        isEditable = false
        isSelectable = false
        isBordered = false
    }
}
