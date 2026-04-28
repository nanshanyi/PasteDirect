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

typealias Expression = SQLite.Expression

enum LoadState: Sendable {
    case idle
    case loading
    case noMore
}

@MainActor
final class PasteDataStore {
    static let main = PasteDataStore()
    var needRefresh = false
    let pageSize = 20

    private(set) var dataList = CurrentValueSubject<[PasteboardModel], Never>([])
    @Published private(set) var loadState: LoadState = .idle
    private var sqlManager = PasteSQLManager()
    private var searchTask: Task<Void, Error>?
    private var loadTask: Task<Void, Error>?
    private var colorCache = ColorCache()

    /// 当前生效的筛选条件（用于分页加载时复用）
    private var currentFilter: Expression<Bool>?
    /// 当前是否为颜色筛选（需要内存过滤）
    private var isColorFilter = false
    /// 已扫描过的 DB 行数（颜色筛选时与展示条数不同）
    private var dbOffset = 0

    func setup() {
        setupData()
    }
}

// MARK: - private 辅助方法

extension PasteDataStore {
    private func setupData() {
        updateTotalCount()
        updateStorageSize()
        dbOffset = pageSize
        Task {
            let list = await fetchItemsFromDB(limit: pageSize, offset: 0)
            dataList.send(list)
            for item in list {
                Task { await self.colorCache.getOrExtract(for: item) }
            }
        }
    }
    
    private func updateTotalCount() {
        let count = sqlManager.totalCount
        SettingsStore.shared.totalCountString = count.description
    }
    
    func updateStorageSize() {
        let size = sqlManager.databaseSize
        SettingsStore.shared.storageSizeString = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
    
    private func fetchItemsFromDB(limit: Int = 50, offset: Int? = nil) async -> [PasteboardModel] {
        let rows = await sqlManager.search(limit: limit, offset: offset)
        return parseItems(rows: rows)
    }
    
    private func parseItems(rows: [Row]) -> [PasteboardModel] {
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
                    length: length ?? 0
                )
            }
            return nil
        }
    }
}

// MARK: - 数据操作 对外接口

extension PasteDataStore {
    /// 加载下一页（支持筛选条件）
    func loadNextPage() {
        guard loadState == .idle else { return }
        loadState = .loading
        loadTask?.cancel()
        loadTask = Task {
            do {
                var accumulated = [PasteboardModel]()
                var offset = dbOffset
                let batchSize = isColorFilter ? pageSize * 3 : pageSize
                while accumulated.count < pageSize {
                    Log("loadNextPage offset=\(offset)")
                    let rows = await sqlManager.search(filter: currentFilter, limit: batchSize, offset: offset)
                    var batch = parseItems(rows: rows)
                    if isColorFilter {
                        batch = batch.filter { $0.hexColorString != nil }
                    }
                    try Task.checkCancellation()
                    accumulated.append(contentsOf: batch)
                    offset += rows.count
                    if rows.count < batchSize { break }
                }
                dbOffset = offset
                dataList.send(dataList.value + accumulated)
                loadState = accumulated.isEmpty ? .noMore : .idle
            } catch {
                loadState = .idle
            }
        }
    }

    func resetDefaultList() {
        currentFilter = nil
        isColorFilter = false
        loadTask?.cancel()
        loadState = .loading
        dbOffset = pageSize
        Task {
            let list = await fetchItemsFromDB(limit: pageSize, offset: 0)
            dataList.send(list)
            loadState = .idle
        }
    }

    /// 数据搜索
    func searchData(_ keyWord: String) {
        searchData(keyWord, filter: .empty)
    }

    /// 带筛选条件的搜索
    func searchData(_ keyWord: String, filter state: FilterState) {
        searchTask?.cancel()
        loadTask?.cancel()
        loadState = .loading
        searchTask = Task {
            var conditions: [Expression<Bool>] = []

            if !keyWord.isEmpty {
                conditions.append(appName.like("%\(keyWord)%") || dataString.like("%\(keyWord)%"))
            }

            if let app = state.selectedApp {
                conditions.append(appName == app)
            }

            if let selectedType = state.selectedType {
                switch selectedType {
                case .string:
                    conditions.append(type == PasteboardType.rtf.rawValue || type == PasteboardType.rtfd.rawValue || type == PasteboardType.string.rawValue)
                case .image:
                    conditions.append(type == PasteboardType.png.rawValue || type == PasteboardType.tiff.rawValue)
                case .color:
                    conditions.append(type == PasteboardType.rtf.rawValue || type == PasteboardType.rtfd.rawValue || type == PasteboardType.string.rawValue)
                case .none:
                    break
                }
            }

            if let dateRange = state.selectedDateRange {
                let interval = dateRange.dateInterval
                conditions.append(date >= interval.start && date < interval.end)
            }

            let combined = conditions.isEmpty ? nil : conditions.dropFirst().reduce(conditions[0]) { $0 && $1 }

            currentFilter = combined
            isColorFilter = state.selectedType == .color

            let rows = await sqlManager.search(filter: combined, limit: pageSize, offset: 0)
            var result = parseItems(rows: rows)

            if isColorFilter {
                result = result.filter { $0.hexColorString != nil }
            }
 
            try Task.checkCancellation()
            dbOffset = pageSize
            dataList.send(result)
            loadState = .idle
        }
    }
    
    /// 增加新数据
    func addNewItem(_ item: NSPasteboardItem) {
        guard let model = PasteboardModel(with: item) else { return }
        insertModel(model)
        Task {
            await extractColor(from: model)
        }
    }
    
    /// 插入数据
    func insertModel(_ model: PasteboardModel) {
        needRefresh = true
        var list = dataList.value
        list.removeAll(where: { $0 == model })
        list.insert(model, at: 0)
        list = Array(list.prefix(pageSize))
        dataList.send(list)
        Task {
            await sqlManager.insert(item: model)
            updateTotalCount()
        }
    }

    /// 删除单条数据
    func deleteItems(_ items: PasteboardModel...) {
        var list = dataList.value
        list.removeAll(where: { items.contains($0) })
        dataList.send(list)
        dbOffset = max(0, dbOffset - items.count)
        deleteItems(filter: items.map { $0.hashValue }.contains(hashKey))
    }
    
    /// 按条件删除数据
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
            let filtered = dataList.value.filter { $0.date > deadDate }
            let hasExpired = filtered.count < dataList.value.count
            if hasExpired {
                dataList.send(filtered)
                needRefresh = true
            }
            Task {
                await sqlManager.delete(filter: date < deadDate)
                updateTotalCount()
            }
        }
    }
    
    /// 删除所有数据
    func clearAllData() {
        sqlManager.clearAllData()
        updateTotalCount()
        resetDefaultList()
    }

    /// 获取常用应用列表（前5个）
    func topApps() -> [(name: String, path: String)] {
        sqlManager.distinctApps(limit: 5)
    }

    /// 获取所有应用列表
    func allApps() -> [(name: String, path: String)] {
        sqlManager.allDistinctApps()
    }
}

// MARK: - 颜色处理

extension PasteDataStore {
    @discardableResult
    func extractColor(from model: PasteboardModel) async -> NSColor? {
        await colorCache.getOrExtract(for: model)
    }
}
