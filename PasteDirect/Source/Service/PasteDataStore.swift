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
    private let sqlManager = PasteSQLManager()
    private var searchTask: Task<Void, Error>?
    private var loadTask: Task<Void, Error>?
    private var colorCache = ColorCache()

    /// 当前生效的筛选参数（Sendable，用于分页加载时复用）
    private var currentKeyword: String = ""
    private var currentFilterState: FilterState = .empty
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
        dbOffset = pageSize
        Task {
            await sqlManager.setup()
            await updateTotalCount()
            await updateStorageSize()
            let list = await sqlManager.search(limit: pageSize, offset: 0)
            dataList.send(list)
            for item in list {
                let icon = NSWorkspace.shared.icon(forFile: item.appPath)
                Task { await self.colorCache.getOrExtract(for: item, icon: icon) }
            }
        }
    }

    private func updateTotalCount() async {
        let count = await sqlManager.totalCount
        SettingsStore.shared.totalCountString = count.description
    }

    func updateStorageSize() async {
        let size = await sqlManager.databaseSize
        SettingsStore.shared.storageSizeString = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - 数据操作 对外接口

extension PasteDataStore {
    /// 加载下一页（支持筛选条件）
    func loadNextPage() {
        guard loadState == .idle else { return }
        loadState = .loading
        loadTask?.cancel()
        let keyword = currentKeyword
        let state = currentFilterState
        let isColor = isColorFilter
        loadTask = Task {
            do {
                var accumulated = [PasteboardModel]()
                var offset = dbOffset
                let batchSize = isColor ? pageSize * 3 : pageSize
                let maxIterations = isColor ? 10 : 1
                var iterations = 0
                var dbExhausted = false
                while accumulated.count < pageSize, iterations < maxIterations {
                    iterations += 1
                    Log("loadNextPage offset=\(offset)")
                    let batch = await sqlManager.searchWithParams(keyword: keyword, state: state, limit: batchSize, offset: offset)
                    let filtered = isColor ? batch.filter { $0.hexColorString != nil } : batch
                    try Task.checkCancellation()
                    accumulated.append(contentsOf: filtered)
                    offset += batch.count
                    if batch.count < batchSize {
                        dbExhausted = true
                        break
                    }
                }
                dbOffset = offset
                dataList.send(dataList.value + accumulated)
                loadState = (accumulated.isEmpty || dbExhausted) ? .noMore : .idle
            } catch {
                loadState = .idle
            }
        }
    }

    func resetDefaultList() {
        currentKeyword = ""
        currentFilterState = .empty
        isColorFilter = false
        loadTask?.cancel()
        loadState = .loading
        dbOffset = pageSize
        Task {
            let list = await sqlManager.search(limit: pageSize, offset: 0)
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
        currentKeyword = keyWord
        currentFilterState = state
        isColorFilter = state.selectedType == .color
        searchTask = Task {
            do {
                let result = await sqlManager.searchWithParams(keyword: keyWord, state: state, limit: pageSize, offset: 0)
                let filtered = isColorFilter ? result.filter { $0.hexColorString != nil } : result
                try Task.checkCancellation()
                dbOffset = pageSize
                dataList.send(filtered)
                loadState = .idle
            } catch {
                loadState = .idle
            }
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
            await updateTotalCount()
        }
    }

    /// 删除单条数据
    func deleteItems(_ items: PasteboardModel...) {
        var list = dataList.value
        list.removeAll(where: { items.contains($0) })
        dataList.send(list)
        dbOffset = max(0, dbOffset - items.count)
        Task {
            for item in items {
                await sqlManager.deleteByHash(item.hashValue)
            }
            await updateTotalCount()
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
                await sqlManager.deleteBeforeDate(deadDate)
                await updateTotalCount()
            }
        }
    }

    /// 删除所有数据
    func clearAllData() {
        Task {
            await sqlManager.clearAllData()
            await updateTotalCount()
            await updateStorageSize()
            resetDefaultList()
        }
    }

    /// 获取常用应用列表（前5个）
    func topApps() async -> [(name: String, path: String)] {
        await sqlManager.distinctApps(limit: 5)
    }

    /// 获取所有应用列表
    func allApps() async -> [(name: String, path: String)] {
        await sqlManager.allDistinctApps()
    }
}

// MARK: - 颜色处理

extension PasteDataStore {
    @discardableResult
    func extractColor(from model: PasteboardModel) async -> NSColor? {
        let icon = NSWorkspace.shared.icon(forFile: model.appPath)
        return await colorCache.getOrExtract(for: model, icon: icon)
    }
}
