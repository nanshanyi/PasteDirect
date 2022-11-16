//
//  HotKey.swift
//  HotKey
//
//  Created by Henry on 2018/09/15.
//  Copyright © 2018 Eonil. All rights reserved.
//

import Carbon
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts {
    static func postCmdVEvent() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        cgEvent?.flags = .maskCommand
        cgEvent?.post(tap: .cghidEventTap)
    }
}

public struct LaunchAtLogin {
    private static let id = "\(Bundle.main.bundleIdentifier!).LaunchAtLogin"
    
    public static var isEnabled: Bool {
        get {
            guard let jobs = (LaunchAtLogin.self as DeprecationWarningWorkaround.Type).jobsDict else {
                return false
            }
            let job = jobs.first { $0["Label"] as! String == id }
            return job?["OnDemand"] as? Bool ?? false
        }
        set {
            SMLoginItemSetEnabled(id as CFString, newValue)
        }
    }
}

private protocol DeprecationWarningWorkaround {
    static var jobsDict: [[String: AnyObject]]? { get }
}

extension LaunchAtLogin: DeprecationWarningWorkaround {
    @available(*, deprecated)
    static var jobsDict: [[String: AnyObject]]? {
        SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: AnyObject]]
    }
}
