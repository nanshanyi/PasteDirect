//
//  KeyCombo.swift
//  HotKey
//
//  Created by Henry on 2018/09/15.
//  Copyright © 2018 Eonil. All rights reserved.
//

import Foundation
import AppKit

public struct KeyCombo {
    /// Same value with `NSEvent.modifierFlags`.
    public var modifierFlags: NSEvent.ModifierFlags
    /// Same value with `NSEvent.keyCode`.
    public var keyCode: UInt16
    public init(modifierFlags: NSEvent.ModifierFlags, keyCode: UInt16) {
        self.modifierFlags = modifierFlags
        self.keyCode = keyCode
    }
}
extension KeyCombo: Hashable {
    public static func == (_ a: KeyCombo, _ b: KeyCombo) -> Bool {
        return a.modifierFlags == b.modifierFlags
            && a.keyCode == b.keyCode
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(modifierFlags.rawValue)
        hasher.combine(keyCode)
    }
}

public func + (_ a: NSEvent.ModifierFlags, _ b: UInt16) -> KeyCombo {
    return KeyCombo(modifierFlags: a, keyCode: b)
}

extension NSEvent {
    func toHotKey() -> KeyCombo {
        return KeyCombo(modifierFlags: modifierFlags, keyCode: keyCode)
    }
}
