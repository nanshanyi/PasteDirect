//
//  Report.swift
//  HotKey
//
//  Created by Henry on 2018/09/15.
//  Copyright © 2018 Eonil. All rights reserved.
//

import Foundation

/// Fatal error reporting facility.
///
/// Some errors are very critical but cannot be handled in normal program flow.
/// For example, if system call in `deinit` returns an error, there's no
/// way to deal with it. And if we have to deal with this, we have to
/// abandon OO design, which is highly undesired.
///
/// This facility provides a way to report such errors and give you a last
/// change to handle and quit program gracefully. Considering fatality of these
/// errors, there's usually no way to recover, graceful quit is would be the
/// best effort.
///
public struct Report {
    public static var delegate: ((FatalIssue) -> Void)? = { err in
        Swift.fatalError("\(err)")
    }
    static func error(_ message: String) {
        assert(false, message)
    }
    static func fatalError(_ e: FatalIssue) {
        assert(false, "\(e)")
        delegate?(e)
    }
}

public extension Report {
    enum FatalIssue {
        case unexpectedErrorInDeinit(Error)
        case unexpectedSystemCallFailureInDeinit(OSStatus)
    }
}
