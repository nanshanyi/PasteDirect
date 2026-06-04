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
    private var ocrCache = OCRCache()

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
        if model.type == .image {
            // 图片走外置流程：原图存文件、列表与 DB 只保留缩略图
            addNewImageItem(model)
        } else {
            insertModel(model)
            Task {
                await extractColor(from: model)
            }
        }
    }

    /// 图片入库：把原图存到文件，生成缩略图后再以缩略图版本插入列表与 DB。
    /// OCR 仍用原图识别(此时列表项已就位，结果能正确回写)。
    private func addNewImageItem(_ original: PasteboardModel) {
        Task {
            let hash = original.hashValue
            let originalData = original.data
            await ImageBlobStore.shared.save(originalData, for: hash)
            // 缩略图生成是 CPU 操作，放后台线程
            let thumb = await Task.detached(priority: .userInitiated) {
                ImageThumbnail.make(from: originalData)
            }.value
            // 缩略图生成失败则降级保留原图 data（仍可显示，只是 DB 略大）
            let model = thumb.map { original.replacingData($0.thumbnail) } ?? original
            insertModel(model)
            await extractColor(from: model)
            if PasteUserDefaults.autoOCRImages {
                await extractOCRText(from: original)
            }
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
                // 图片连带删除外置的原图文件
                if item.type == .image {
                    await ImageBlobStore.shared.delete(for: item.hashValue)
                }
            }
            await updateTotalCount()
            // 删除后列表可能不足一屏,导致横向列表无法滚动、再也触发不了分页加载;
            // 这里主动补加载,把可见列表补回至少一页(DB 仍有数据时)。
            refillIfNeeded()
        }
    }

    /// 当前展示条数不足一页且仍可加载时,主动加载下一页补满。
    /// loadNextPage 内部会在 DB 耗尽时置 .noMore,故无需在此预判总数。
    private func refillIfNeeded() {
        guard loadState == .idle else { return }
        guard dataList.value.count < pageSize else { return }
        loadNextPage()
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
                // 先取得将被删除的图片 hash，删 DB 后再清理对应的外置原图文件
                let imageHashes = await sqlManager.imageHashesBeforeDate(deadDate)
                await sqlManager.deleteBeforeDate(deadDate)
                for hash in imageHashes {
                    await ImageBlobStore.shared.delete(for: hash)
                }
                // 过期清理是低频时机(每天最多一次)，且常删掉大量数据，
                // 顺手 VACUUM 把空闲页还给磁盘，避免库文件只增不减。
                if hasExpired || !imageHashes.isEmpty {
                    await sqlManager.vacuum()
                }
                await updateTotalCount()
                await updateStorageSize()
            }
        }
    }

    /// 删除所有数据
    func clearAllData() {
        Task {
            await sqlManager.clearAllData()
            await ImageBlobStore.shared.deleteAll()
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

// MARK: - 图片原图按需加载

extension PasteDataStore {
    /// 加载图片原图数据。原图已外置到文件，列表中 model 持有的是缩略图。
    /// 文件缺失(迁移中/异常)时降级返回 model.data(可能是缩略图或旧的原图 BLOB)。
    /// 非图片项直接返回 model.data。
    func loadOriginalImageData(for model: PasteboardModel) async -> Data {
        guard model.type == .image else { return model.data }
        if let data = await ImageBlobStore.shared.load(for: model.hashValue) {
            return data
        }
        return model.data
    }
}

// MARK: - OCR 处理

extension PasteDataStore {
    /// 对图片做 OCR,识别成功后把文本写回该图片 model 的 ocrText 字段(内存 + DB),
    /// 让图片内容可被搜索;不产生新的列表条目。
    @discardableResult
    func extractOCRText(from model: PasteboardModel) async -> String? {
        // 已识别过则跳过(手动入口重复触发时省去一次 Vision 调用)
        guard model.ocrText == nil else { return model.ocrText }

        // 列表中的 model 持有缩略图(512px),OCR 必须用原图否则会丢字;
        // 按需加载原图,构造一个临时的原图版本交给 OCRCache(cache key 用 hashValue 不受影响)。
        let modelForOCR: PasteboardModel
        if model.type == .image {
            let originalData = await loadOriginalImageData(for: model)
            modelForOCR = originalData == model.data ? model : model.replacingData(originalData)
        } else {
            modelForOCR = model
        }

        let text = await ocrCache.getOrExtract(for: modelForOCR)
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 回写内存列表中对应的图片项(若仍在当前列表中)
        var list = dataList.value
        if let idx = list.firstIndex(where: { $0.hashValue == model.hashValue }) {
            list[idx] = list[idx].withOCRText(trimmed)
            dataList.send(list)
        }
        // 回写数据库
        await sqlManager.updateOCRText(trimmed, forHash: model.hashValue)
        return trimmed
    }
}
