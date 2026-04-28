//
//  PasteUserDefaults.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import Foundation

@MainActor
enum PasteUserDefaults {
    @UserDefaultsWrapper(.onStart, defaultValue: true)
    static var onStart
    @UserDefaultsWrapper(.statusDisplay, defaultValue: true)
    static var statusDisplay
    @UserDefaultsWrapper(.pasteDirect, defaultValue: true)
    static var pasteDirect
    @UserDefaultsWrapper(.pasteOnlyText, defaultValue: false)
    static var pasteOnlyText
    @UserDefaultsWrapper(.historyTime, defaultValue: HistoryTime.week.rawValue)
    static var historyTime
    @UserDefaultsWrapper(.appAlreadyLaunched, defaultValue: false)
    static var appAlreadyLaunched
    @UserDefaultsWrapper(.lastClearDate, defaultValue: "")
    static var lastClearDate
    @UserDefaultsWrapper(.ignoreList, defaultValue: [String]())
    static var ignoreList

    static func setValue<T>(for key: PrefKey, value: T) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}

@propertyWrapper
struct UserDefaultsWrapper<T> {
    let key: PrefKey
    let defaultValue: T

    init(_ key: PrefKey, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key.rawValue) }
    }
}
