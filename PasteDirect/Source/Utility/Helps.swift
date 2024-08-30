//
//  LaunchAtLogin.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/6/10.
//

import Foundation
import ServiceManagement

struct LaunchAtLogin {
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
        enable ? try register() : try unregister()
    }
}



