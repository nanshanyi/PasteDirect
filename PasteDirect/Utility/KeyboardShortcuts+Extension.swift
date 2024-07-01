//
//  KeyboardShortcuts+Extension.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/15.
//

import Carbon
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pasteKey = Self("pasteShortcurs", default: Shortcut(.v, modifiers: [.command, .shift]))
}

extension KeyboardShortcuts {
    static func postCmdVEvent() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        cgEvent?.flags = .maskCommand
        cgEvent?.post(tap: .cghidEventTap)
    }
}
