//
//  PasteDataStore.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation
import Combine
import SwiftUI
import SQLite
import UIColorHexSwift

typealias Expression = SQLite.Expression

final class PasteDataStore {
    static let main = PasteDataStore()
    var needRefresh = false
    let pageSize = 50

    private(set) var dataList = CurrentValueSubject<[PasteboardModel], Never>([])
    private(set) var totalCount = 0
    private(set) var pageIndex = 0
    private var currentOffset: Int { pageSize * pageIndex }
    private var sqlManager = PasteSQLManager()
    private var searchTask: Task<Void, Error>?
    private var colorCache = ColorCache()

    func setup() {
        setupData()
    }
}

// MARK: - private 辅助方法

extension PasteDataStore {
    private func setupData() {
        pageIndex = 0
        updateTotalCount()
        Task {
            let list = await fetchItemsFromDB(limit: pageSize, offset: currentOffset)
            dataList.send(list)
            await withTaskGroup(of: Void.self) { group in
                for item in list {
                    group.addTask {
                        await self.colorCache.getOrExtract(for: item)
                    }
                }
            }
        }
    }
    
    private func updateTotalCount() {
        totalCount = sqlManager.totalCount
        Task { @MainActor in
            SettingsStore.shared.totalCountString = totalCount.description
        }
    }
    
    private func fetchItemsFromDB(limit: Int = 50, offset: Int? = nil) async -> [PasteboardModel] {
        let rows = await sqlManager.search(limit: limit, offset: offset)
        return await parseItems(rows: rows)
    }
    
    private func parseItems(rows: [Row]) async -> [PasteboardModel] {
        return rows.compactMap { row in
            if let type = try? row.get(type),
               let data = try? row.get(data),
               let hashV = try? row.get(hashKey),
               let date = try? row.get(date) {
                let appName = try? row.get(appName)
                let appPath = try? row.get(appPath)
                let showData = try? row.get(showData) ?? data
                let dataString = try? row.get(dataString)
                let length = try? row.get(length)
                let pType = PasteboardType(type)
                
                return PasteboardModel(
                    pasteboardType: pType,
                    data: data,
                    showData: showData,
                    hashValue: hashV,
                    date: date,
                    appPath: appPath ?? "",
                    appName: appName ?? "",
                    dataString: dataString ?? "",
                    length: length ?? 0,
                    attributeString: NSAttributedString(with: showData, type: pType)
                )
            }
            return nil
        }
    }
}

// MARK: - 数据操作 对外接口

extension PasteDataStore {
    /// 加载下一页
    /// - Returns: 返回从0到当前页所有数据list
    func loadNextPage() {
        guard dataList.value.count < totalCount else { return }
        pageIndex += 1
        Task {
            Log("loadNextPage \(pageIndex)")
            let nextPage = await fetchItemsFromDB(limit: pageSize, offset: currentOffset)
            dataList.send(dataList.value + nextPage)
        }
    }
    
    func resetDefaultList() {
        pageIndex = 0
        Task {
            let list = await fetchItemsFromDB(limit: pageSize, offset: currentOffset)
            dataList.send(list)
        }
    }
    
    /// 数据搜索
    /// - Parameter keyWord: 搜索关键词
    /// - Returns: 搜索结果list
    func searchData(_ keyWord: String) {
        searchTask?.cancel()
        searchTask = Task {
            let filter = appName.like("%\(keyWord)%") || dataString.like("%\(keyWord)%")
            let rows = await sqlManager.search(filter: filter)
            let result = await parseItems(rows: rows)
            try Task.checkCancellation()
            dataList.send(result)
        }
    }
    
    /// 增加新数据
    /// - Parameter item: 新的item
    func addNewItem(_ item: NSPasteboardItem) {
        guard let model = PasteboardModel(with: item) else { return }
        insertModel(model)
        Task {
            await extractColor(from: model)
        }
    }
    
    /// 插入数据
    /// - Parameter model: PasteboardModel
    func insertModel(_ model: PasteboardModel) {
        needRefresh = true
        Task {
            await sqlManager.insert(item: model)
            updateTotalCount()
            var list = dataList.value
            list.removeAll(where: { $0 == model })
            list.insert(model, at: 0)
            list = Array(list.prefix(pageSize))
            dataList.send(list)
        }
    }

    /// 删除单条数据
    /// - Parameter item: PasteboardModel
    func deleteItems(_ items: PasteboardModel...) {
        var list = dataList.value
        list.removeAll(where: { items.contains($0) })
        dataList.send(list)
        deleteItems(filter: items.map { $0.hashValue }.contains(hashKey))
    }
    
    /// 按条件删除数据
    /// - Parameter filter: Expression<Bool>
    func deleteItems(filter: Expression<Bool>) {
        Task {
            await sqlManager.delete(filter: filter)
            updateTotalCount()
            resetDefaultList()
        }
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
            dateCom = DateComponents(calendar: Calendar.current)
        case .day:
            dateCom = DateComponents(calendar: Calendar.current, day: -1)
        case .week:
            dateCom = DateComponents(calendar: Calendar.current, day: -7)
        case .month:
            dateCom = DateComponents(calendar: Calendar.current, month: -1)
        default:
            return
        }
        if let deadDate = Calendar.current.date(byAdding: dateCom, to: Date()) {
            dataList.send(dataList.value.filter { $0.date > deadDate })
            deleteItems(filter: date < deadDate)
            needRefresh = true
        }
    }
    
    /// 删除所有数据
    func clearAllData() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear all clipboard history")
        alert.informativeText = String(localized: "This action cannot be undone. All clipboard data will be permanently deleted.")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Clear"))
        alert.alertStyle = .warning
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            sqlManager.clearAllData()
            updateTotalCount()
            resetDefaultList()
        }
    }
}

// MARK: - 颜色处理

extension PasteDataStore {
    @discardableResult
    func extractColor(from model: PasteboardModel) async -> NSColor? {
        await colorCache.getOrExtract(for: model)
    }
}
