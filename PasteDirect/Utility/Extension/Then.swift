//
//  Then.swift
//  PasteDirect
//
//  Created by 南山忆 on 2023/12/21.
//

import Foundation

// MARK: - Then

public protocol Then {}

public extension Then where Self: AnyObject {
    @inlinable
    func then(_ block: (Self) throws -> Void) rethrows -> Self {
        try block(self)
        return self
    }
}

// MARK: - NSObject + Then

extension NSObject: Then {}
