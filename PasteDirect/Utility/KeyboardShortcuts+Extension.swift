//
//  KeyboardShortcuts+Extension.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/15.
//

import Foundation
import KeyboardShortcuts
extension KeyboardShortcuts.Name {
    
    static let pasteKey = Self("pasteShortcurs", default: Shortcut(.v,modifiers:[.command, .shift]))
}
