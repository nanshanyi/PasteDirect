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

@MainActor
final class PasteDataStore {
    static let main = PasteDataStore()
    let pageSize = 20

    /// 数据库内容变化的原因
    enum Change {
        /// 用户删除了条目（列表可能变短，需要补页）
        case userDeleted
        /// 其他变化：写入、置顶、OCR 回写、清理等
        case other
    }

    /// 数据库内容有变化，且已经写完。列表据此重新查询。
    let didChange = PassthroughSubject<Change, Never>()
    private let sqlManager = PasteSQLManager()
    private var colorCache = ColorCache()
    private var resolvedAppColors = [String: NSColor?]()
    private var ocrCache = OCRCache()

    func setup() {
        setupData()
    }
}

// MARK: - private 辅助方法

extension PasteDataStore {
    private func setupData() {
        Task {
            await sqlManager.setup()
            #if DEBUG
            await seedDemoDataIfNeeded()
            #endif
            await updateTotalCount()
            await updateStorageSize()
            didChange.send(.other)
            // 预先提取首屏 App 主色，避免第一次打开时卡片头部颜色闪变
            for item in await sqlManager.fetchPage(limit: pageSize).items {
                Task { await self.extractColor(from: item) }
            }
        }
    }

    #if DEBUG
    /// 演示模式且演示库为空时写入演示数据
    private func seedDemoDataIfNeeded() async {
        guard DemoData.isEnabled, await sqlManager.totalCount == 0 else { return }
        for entry in DemoData.makeEntries() {
            if let original = entry.original {
                await ImageBlobStore.shared.save(original, for: entry.model.hashValue)
            }
            await sqlManager.insert(item: entry.model)
        }
    }
    #endif

    private func updateTotalCount() async {
        let count = await sqlManager.totalCount
        SettingsStore.shared.totalCountString = count.description
    }

    func updateStorageSize() async {
        // 数据库 + 外置图片原图文件，两者相加才是实际占用
        let dbSize = await sqlManager.databaseSize
        let imageSize = await ImageBlobStore.shared.totalSize()
        let total = Int64(dbSize) + Int64(imageSize)
        SettingsStore.shared.storageSizeString = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}

// MARK: - 数据操作 对外接口

extension PasteDataStore {
    /// 取 cursor 之后的一页，cursor 为 nil 时取第一页
    func fetchPage(keyword: String, state: FilterState, after cursor: PageCursor?) async -> PastePage {
        await sqlManager.fetchPage(keyword: keyword, state: state, after: cursor, limit: pageSize)
    }

    /// 重新取从第一条到 cursor（含）的所有行；cursor 为 nil 时取全部匹配行
    func fetchThrough(keyword: String, state: FilterState, cursor: PageCursor?) async -> [PasteboardModel] {
        await sqlManager.fetchThrough(keyword: keyword, state: state, cursor: cursor)
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

    /// 图片入库：原图转 PNG 存文件，列表与 DB 只存缩略图。
    /// 剪贴板常给未压缩 TIFF(可达数 MB)，转 PNG 后磁盘占用小一个数量级。
    private func addNewImageItem(_ original: PasteboardModel) {
        Task {
            let hash = original.hashValue
            let rawData = original.data
            let rawType = original.pasteboardType
            // 重编码 + 缩略图都是 CPU 操作，放后台线程；重编码失败则保留原始字节与类型
            let processed = await Task.detached(priority: .userInitiated) { () -> (stored: Data, type: PasteboardType, thumb: Data?) in
                let png = ImageThumbnail.reencodeAsPNG(from: rawData)
                let thumb = ImageThumbnail.make(from: rawData)?.thumbnail
                return (png ?? rawData, png != nil ? .png : rawType, thumb)
            }.value
            // 文件名用原图 hash，去重/主键不受转码影响
            await ImageBlobStore.shared.save(processed.stored, for: hash)
            // type 同步为落盘类型，保证粘贴回写时类型与文件字节一致；缩略图失败则降级用转码后原图
            let model = original.replacingData(processed.thumb ?? processed.stored, type: processed.type)
            insertModel(model)
            await extractColor(from: model)
            if PasteUserDefaults.autoOCRImages {
                // OCR 用内存里的原图字节，结果按 hashValue 回写
                await extractOCRText(from: original)
            }
        }
    }

    /// 插入数据（同内容已存在时更新为最新一次，置顶状态由数据库保留）
    func insertModel(_ model: PasteboardModel) {
        Task {
            if await sqlManager.insert(item: model) {
                didChange.send(.other)
            }
            await updateTotalCount()
        }
    }

    /// 设置/取消某条目的置顶状态
    func setPinned(_ pinned: Bool, for model: PasteboardModel) {
        let newDate: Date? = pinned ? Date() : nil
        Task {
            await sqlManager.updatePinned(newDate, forHash: model.hashValue)
            didChange.send(.other)
        }
    }

    /// 删除单条数据
    func deleteItems(_ items: PasteboardModel...) {
        Task {
            for item in items {
                await sqlManager.deleteByHash(item.hashValue)
                // 图片连带删除外置的原图文件
                if item.type == .image {
                    await ImageBlobStore.shared.delete(for: item.hashValue)
                }
            }
            didChange.send(.userDeleted)
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
            Task {
                // 先取得将被删除的图片 hash，删 DB 后再清理对应的外置原图文件
                let imageHashes = await sqlManager.imageHashesBeforeDate(deadDate)
                let removed = await sqlManager.deleteBeforeDate(deadDate)
                for hash in imageHashes {
                    await ImageBlobStore.shared.delete(for: hash)
                }
                // 过期清理是低频时机(每天最多一次)，且常删掉大量数据，
                // 顺手 VACUUM 把空闲页还给磁盘，避免库文件只增不减。
                if removed > 0 {
                    didChange.send(.other)
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
            didChange.send(.other)
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
    func typeCounts() async -> TypeCounts {
        await sqlManager.typeCounts()
    }

    @discardableResult
    func extractColor(from model: PasteboardModel) async -> NSColor? {
        let icon = NSWorkspace.shared.icon(forFile: model.appPath)
        let color = await colorCache.getOrExtract(for: model, icon: icon)
        resolvedAppColors[model.appPath] = .some(color)
        return color
    }

    /// 已提取过的 App 主色,同步读取供卡片复用时立即上色(外层 nil 表示尚未提取)
    func cachedColor(for model: PasteboardModel) -> NSColor?? {
        resolvedAppColors[model.appPath]
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

        await sqlManager.updateOCRText(trimmed, forHash: model.hashValue)
        didChange.send(.other)
        return trimmed
    }
}
