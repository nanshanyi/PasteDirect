//
//  PasteUserDefaults.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import Foundation

enum PasteUserDefaults {
    /// 开机自启
    @UserDefaultsWrapper(.onStart, defaultValue: true)
    static var onStart
    /// 直接粘贴
    @UserDefaultsWrapper(.pasteDirect, defaultValue: true)
    static var pasteDirect
    /// 粘贴为纯文本
    @UserDefaultsWrapper(.pasteOnlyText, defaultValue: false)
    static var pasteOnlyText
    /// 历史容量时间
    @UserDefaultsWrapper(.historyTime, defaultValue: HistoryTime.week.rawValue)
    static var historyTime
    /// 是否启动过App
    @UserDefaultsWrapper(.appAlreadyLaunched, defaultValue: false)
    static var appAlreadyLaunched
    /// 本地APP颜色表
    @UserDefaultsWrapper(.appColorData, defaultValue: [String: String]())
    static var appColorData
    /// 上次清理时间
    @UserDefaultsWrapper(.lastClearDate, defaultValue: "")
    static var lastClearDate
    /// 忽略的APP
    @UserDefaultsWrapper(.ignoreList, defaultValue: [String]())
    static var ignoreList
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
        get {
            UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key.rawValue)
        }
    }
}
