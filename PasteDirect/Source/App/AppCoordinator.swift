//
//  AppCoordinator.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Foundation

@MainActor
protocol AppCoordinator: AnyObject {
    var frontAppName: String? { get }
    func activateFrontApp()
    func dismissWindow(_ completionHandler: (() -> Void)?)
    func showSettings(category: SettingCategory?)
    func setStatusItemVisible(_ isVisible: Bool)
}

extension AppCoordinator {
    func dismissWindow() { dismissWindow(nil) }
    func showSettings() { showSettings(category: nil) }
}

enum AppContext {
    @MainActor private static var _coordinator: AppCoordinator?

    @MainActor static var coordinator: AppCoordinator {
        get {
            guard let c = _coordinator else {
                fatalError("AppContext.coordinator accessed before applicationDidFinishLaunching")
            }
            return c
        }
        set { _coordinator = newValue }
    }
}
