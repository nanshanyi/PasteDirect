//
//  PrefKey.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Foundation

enum PrefKey: String {
    /// 开机自启
    case onStart
    /// 直接粘贴
    case pasteDirect
    /// 粘贴为纯文本
    case pasteOnlyText
    /// 历史容量时间
    case historyTime
    /// 是否启动过App
    case appAlreadyLaunched
    /// 本地APP颜色表
    case appColorData
    /// 上次清理时间
    case lastClearDate
    /// 忽略的APP
    case ignoreList
}

enum HistoryTime: Int {
    case now = -1
    case day = 0
    case week = 33
    case month = 66
    case forever = 100
}
