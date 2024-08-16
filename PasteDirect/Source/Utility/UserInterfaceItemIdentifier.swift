//
//  UserInterfaceItemIdentifier.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/26.
//

import Cocoa

protocol UserInterfaceItemIdentifier {
    static var identifier: NSUserInterfaceItemIdentifier { get }
    static var nib: NSNib? { get }
}

extension UserInterfaceItemIdentifier {
    static var identifier: NSUserInterfaceItemIdentifier { .init(rawValue: String(describing: Self.self)) }
    static var nib: NSNib? {
        FileManager.default.fileExists(atPath: Bundle.main.path(forResource: String(describing: Self.self), ofType: "nib") ?? "") ?
            NSNib(nibNamed: String(describing: Self.self), bundle: Bundle.main) : nil
    }
}

