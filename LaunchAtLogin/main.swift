//
//  main.swift
//  LaunchAtLogin
//
//  Created by 南山忆 on 2022/11/16.
//

import Cocoa
func main() {
    let mainBundleId = Bundle.main.bundleIdentifier!.replacingOccurrences(of: ".LaunchAtLogin", with: "")
    
    if !NSRunningApplication.runningApplications(withBundleIdentifier: mainBundleId).isEmpty {
        exit(0)
    }
    
    let pathComponents = (Bundle.main.bundlePath as NSString).pathComponents
    let mainPath = NSString.path(withComponents: Array(pathComponents[0...(pathComponents.count - 5)]))
    NSWorkspace.shared.launchApplication(mainPath)
    
    exit(0)
}

main()
