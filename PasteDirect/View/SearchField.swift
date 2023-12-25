//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa

class SearchField: NSSearchField {
    
    public var isEditing = false
    
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        isEditing = true
        return super.becomeFirstResponder()
    }
    
    @discardableResult
    override func resignFirstResponder() -> Bool {
        isEditing = false
        return super.resignFirstResponder()
    }
}
