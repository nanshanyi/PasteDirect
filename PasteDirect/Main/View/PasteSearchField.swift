//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa

class PasteSearchField: NSSearchField {
    
    public var isEditing = false
    public var isFirstResponder: Bool {
        currentEditor() != nil && currentEditor() == window?.firstResponder
    }
    
    override var canBecomeKeyView: Bool {
        true
    }
    
    override var acceptsFirstResponder: Bool {
        true
    }
}
