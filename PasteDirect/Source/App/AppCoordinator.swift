//
//  AppCoordinator.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/23.
//

import Foundation

protocol AppCoordinator: AnyObject {
    var frontAppName: String? { get }
    func activateFrontApp()
    func dismissWindow(_ completionHandler: (() -> Void)?)
    func showSettings()
    func setStatusItemVisible(_ isVisible: Bool)
}

extension AppCoordinator {
    func dismissWindow() { dismissWindow(nil) }
}

enum AppContext {
    static var coordinator: AppCoordinator!
}
