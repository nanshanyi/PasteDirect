//
//  HotKey.swift
//  HotKey
//
//  Created by Henry on 2018/09/15.
//  Copyright © 2018 Eonil. All rights reserved.
//

import Foundation
import ServiceManagement

struct LaunchAtLogin {
    private static let id = "\(Bundle.main.bundleIdentifier!).LaunchAtLogin"

    static var isEnabled: Bool {
        get {
            SMAppService.mainApp.isEnabled
        }
        set {
            do {
                try SMAppService.mainApp.update(newValue)
            } catch {
                Log("Failed to update launch at login: \(error)")
            }
        }
    }
}

private extension SMAppService {
    var isEnabled: Bool {
        status == .enabled
    }
    
    func update(_ enable: Bool) throws {
        isEnabled ? try unregister() : try register()
    }
}
