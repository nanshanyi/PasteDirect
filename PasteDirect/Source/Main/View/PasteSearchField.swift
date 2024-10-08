//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa

final class PasteSearchField: NSSearchField {
    var isEditing = false
    var isFirstResponder: Bool {
        currentEditor() != nil && currentEditor() == window?.firstResponder
    }
    
    override var canBecomeKeyView: Bool {
        true
    }
    
    override var acceptsFirstResponder: Bool {
        true
    }
}
