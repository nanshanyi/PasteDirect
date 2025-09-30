//
//  SettingStore.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/30.
//

import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    @Published var settings: [PrefKey: Any] = [:]
    @Published var totalCountString: String = ""
    init() {
        loadDefaultSettings()
    }
    
    private func loadDefaultSettings() {
        settings = [
            .onStart: PasteUserDefaults.onStart,
            .statusDisplay: PasteUserDefaults.statusDisplay,
            .pasteDirect: PasteUserDefaults.pasteDirect,
            .pasteOnlyText: PasteUserDefaults.pasteOnlyText,
            .historyTime: PasteUserDefaults.historyTime,
            .appAlreadyLaunched: PasteUserDefaults.appAlreadyLaunched,
            .lastClearDate: PasteUserDefaults.lastClearDate,
            .ignoreList: PasteUserDefaults.ignoreList,
        ]
    }
    
    func getBool(_ key: PrefKey, defaultValue: Bool = false) -> Bool {
        return settings[key] as? Bool ?? defaultValue
    }
    
    func getInt(_ key: PrefKey, defaultValue: Int = 0) -> Int {
        return settings[key] as? Int ?? defaultValue
    }
    
    func setBool(_ key: PrefKey, value: Bool) {
        settings[key] = value
        PasteUserDefaults.setValue(for: key, value: value)
        switch key {
        case .onStart:
            LaunchAtLogin.isEnabled = value
        case .statusDisplay:
            let app = NSApplication.shared.delegate as? PasteAppDelegate
            app?.statusItemVisible(value)
        default:
            break
        }
    }
    
    func setInt(_ key: PrefKey, value: Int) {
        settings[key] = value
        PasteUserDefaults.setValue(for: key, value: value)
        if key == .historyTime, let type = HistoryTime(rawValue: value) {
            PasteDataStore.main.clearData(for: type)
        }
    }
}
