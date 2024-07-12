//
//  PasteDataStore.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation
import RxRelay
import RxSwift
import SQLite
import UIColorHexSwift

class PasteDataStore {
    static let main = PasteDataStore()
    var dataList: [PasteboardModel] = []
    var totoalCount = BehaviorRelay<Int>(value: 0)
    var dataChange = false
    
    private var sqlManager = PasteSQLManager.manager
    private var colorDic = [String: String]()
    private var pageIndex = 1
    private let pageSize = 50

    init() {
        dataList = getItems(limit: pageIndex * pageSize)
        totoalCount.accept(sqlManager.totoalCount)
        colorDic = PasteUserDefaults.appColorData
    }
}

// MARK: - private 辅助方法

extension PasteDataStore {
    private func updateTotoalCount() {
        totoalCount.accept(sqlManager.totoalCount)
    }

    private func getItems(limit: Int = 50, offset: Int? = nil) -> [PasteboardModel] {
        let rows = sqlManager.search(limit: limit, offset: offset)
        return getItems(rows: rows)
    }

    private func getItems(rows: [Row]) -> [PasteboardModel] {
        var item: PasteboardModel
        var items = [PasteboardModel]()
        for row in rows {
            if let type = try? row.get(type),
               let data = try? row.get(data),
               let hashV = try? row.get(hashKey),
               let date = try? row.get(date)
            {
                let appName = try? row.get(appName)
                let appPath = try? row.get(appPath)
                item = PasteboardModel(pasteBoardType: PasteboardType(rawValue: type)!, 
                                       data: data,
                                       hashValue: hashV,
                                       date: date,
                                       appPath: appPath ?? "",
                                       appName: appName ?? "")
                items.append(item)
            }
        }
        return items
    }
}

// MARK: - 数据操作 对外接口

extension PasteDataStore {
    
    /// 加载下一页
    /// - Returns: 返回从0到当前页所有数据list
    func loadNextPage() async -> [PasteboardModel] {
        withUnsafeCurrentTask { _ in
            Log("loadNextPage\(Thread.current)")
            if dataList.count < totoalCount.value {
                dataList += getItems(limit: pageSize, offset: pageSize * pageIndex)
                pageIndex += 1
            }
            return dataList
        }
    }

    /// 数据搜索
    /// - Parameter keyWord: 搜索关键词
    /// - Returns: 搜索结果list
    func searchData(_ keyWord: String) async -> [PasteboardModel] {
        withUnsafeCurrentTask { _ in
            let rows = sqlManager.search(filter: appName.like("%\(keyWord)%") || dataString.like("%\(keyWord)%"))
            return getItems(rows: rows)
        }
    }
    
    /// 增加新数据
    /// - Parameter item: 新的item
    func addNewItem(_ item: NSPasteboardItem) {
        guard let model = PasteboardModel(with: item) else { return }
        sqlManager.insert(item: model)
        updateTotoalCount()
        dataChange = true
        dataList.removeAll(where: { $0 == model })
        dataList.insert(model, at: 0)
        Task {
            await updateColor(model)
        }
    }

    /// 移动已有数据
    /// - Parameter model: PasteboardModel
    func addOldModel(_ model: PasteboardModel) {
        sqlManager.insert(item: model)
        updateTotoalCount()
        dataChange = true
        dataList.removeAll(where: { $0 == model })
        dataList.insert(model, at: 0)
    }

    /// 删除单条数据
    /// - Parameter item: PasteboardModel
    func deleteItem(_ item: PasteboardModel) {
        dataList.removeAll(where: { $0 == item })
        deleteItems(filter: hashKey == item.hashValue)
    }

    /// 按条件删除数据
    /// - Parameter filter: Expression<Bool>
    func deleteItems(filter: Expression<Bool>) {
        sqlManager.delete(filter: filter)
        updateTotoalCount()
    }

    /// 删除过期数据
    func clearExpiredData() {
        let lastDate = PasteUserDefaults.lastClearDate
        let dateStr = Date().formatted(date: .numeric, time: .omitted)
        if lastDate == dateStr { return }
        PasteUserDefaults.lastClearDate = dateStr
        let current = PasteUserDefaults.historyTime
        guard let type = HistoryTime(rawValue: current) else { return }
        clearData(for: type)
    }

    /// 按时间类型删除数据
    /// - Parameter type: HistoryTime
    func clearData(for type: HistoryTime) {
        var dateCom = DateComponents()
        switch type {
        case .now:
            dateCom = DateComponents(calendar: NSCalendar.current)
        case .day:
            dateCom = DateComponents(calendar: NSCalendar.current, day: -1)
        case .week:
            dateCom = DateComponents(calendar: NSCalendar.current, day: -7)
        case .month:
            dateCom = DateComponents(calendar: NSCalendar.current, month: -1)
        default:
            return
        }
        if let deadDate = NSCalendar.current.date(byAdding: dateCom, to: Date()) {
            dataList.removeAll(where: { $0.date < deadDate })
            deleteItems(filter: date < deadDate)
        }
    }

    /// 删除所有数据
    func clearAllData() {
        dataList.removeAll()
        clearData(for: .now)
        updateTotoalCount()
    }
}

// MARK: - 颜色处理

extension PasteDataStore {
    @discardableResult
    func updateColor(_ model: PasteboardModel) async -> NSColor {
        withUnsafeCurrentTask { _ in
            if !colorDic.contains(where: { $0.key == model.appName }) {
                let iconImage = NSWorkspace.shared.icon(forFile: model.appPath)
                let colors = iconImage.getColors(quality: .highest)
                if let colorStr = colors?.primary.hexString(true),
                   !colorStr.isEmpty
                {
                    colorDic[model.appName] = colorStr
                    PasteUserDefaults.appColorData = colorDic
                }
                return colors?.primary ?? .clear
            }
            return .clear
        }
    }

    func colorWith(_ model: PasteboardModel) async -> NSColor {
        if let colorStr = colorDic[model.appName], let color = NSColor(colorStr) {
            return color
        }
        return await updateColor(model)
    }
}
