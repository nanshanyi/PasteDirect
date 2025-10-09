//
//  SearchField.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/22.
//

import Cocoa
import Combine

final class PasteSearchField: NSSearchField {
    var isEditing = false
    var isFirstResponder: Bool {
        currentEditor() != nil && currentEditor() == window?.firstResponder
    }

    @Published private(set) var text: String = ""

    override var stringValue: String {
        didSet {
            if stringValue != text {
                text = stringValue
            }
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        text = stringValue
    }

    override var canBecomeKeyView: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }
}
