//
//  PasteSQLManager.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/1.
//

import Foundation
@preconcurrency import SQLite

typealias Expression = SQLite.Expression

struct TypeCounts: Sendable, Equatable {
    var text = 0
    var image = 0
    /// 派生类型(颜色/链接等)的条数,按 kind 标签统计
    var derived: [PasteModelType: Int] = [:]

    func count(for type: PasteModelType) -> Int? {
        switch type {
        case .string: return text
        case .image: return image
        case .none: return nil
        default: return derived[type] ?? 0
        }
    }
}

actor PasteSQLManager {

    // MARK: - Column Definitions

    private let col_id = Expression<Int>("id")
    private let col_hashKey = Expression<Int>("hashKey")
    private let col_type = Expression<String>("type")
    private let col_data = Expression<Data>("data")
    private let col_showData = Expression<Data?>("showData")
    private let col_date = Expression<Date>("date")
    private let col_appPath = Expression<String>("appPath")
    private let col_appName = Expression<String>("appName")
    private let col_dataString = Expression<String>("dataString")
    private let col_length = Expression<Int>("length")
    private let col_ocrText = Expression<String?>("ocrText")
    private let col_imgW = Expression<Int?>("imgW")
    private let col_imgH = Expression<Int?>("imgH")
    private let col_pinnedDate = Expression<Date?>("pinnedDate")
    /// 派生类型编号(PasteModelType 的固定整数 rawValue),其他为 NULL。写入时打好,筛选与计数直接走 SQL
    private let col_kind = Expression<Int?>("kindCode")

    // MARK: - DB

    private static let tableName = "pasteContent"
    /// 表结构与规则版本。调整颜色/链接识别规则时递增，低于此版本的库启动时会重新回填 kindCode。
    private static let schemaVersion: Int32 = 3

    private let dbPath: String
    private var db: Connection?
    private let table: Table

    /// - Parameter dbPath: 数据库文件路径。默认 nil 走生产路径(Application Support/paste/paste.sqlite3);
    ///   测试可传入临时路径,避免污染用户的真实剪贴板历史库。
    init(dbPath: String? = nil) {
        let path: String
        if let dbPath {
            path = dbPath
        } else {
            let appSupportDir = NSSearchPathForDirectoriesInDomains(
                .applicationSupportDirectory, .userDomainMask, true
            ).first ?? NSTemporaryDirectory()
            path = appSupportDir.appending("/\(StorageLocation.folderName)/paste.sqlite3")
        }
        let dirPath = (path as NSString).deletingLastPathComponent
        var isDir = ObjCBool(false)
        let filExist = FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir)
        if !filExist || !isDir.boolValue {
            try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        self.dbPath = path

        do {
            let conn = try Connection(path)
            conn.busyTimeout = 5.0
            self.db = conn
        } catch {
            Log("Connection Error\(error)")
            self.db = nil
        }
        self.table = Table(Self.tableName)
    }

    /// 初始化表结构，需在首次使用前调用
    func setup() {
        guard let db else { return }
        do {
            try db.run(table.create(ifNotExists: true, withoutRowid: false) { t in
                t.column(col_id, primaryKey: true)
                t.column(col_hashKey); t.column(col_type); t.column(col_data)
                t.column(col_showData); t.column(col_date); t.column(col_appPath)
                t.column(col_appName); t.column(col_dataString); t.column(col_length)
                t.column(col_ocrText); t.column(col_imgW); t.column(col_imgH)
                t.column(col_pinnedDate); t.column(col_kind)
            })
            try addMissingColumns(on: db)
            try db.run(table.createIndex(col_date, ifNotExists: true))
            try db.run(table.createIndex(col_appName, ifNotExists: true))
            try db.run(table.createIndex(col_type, ifNotExists: true))
            try db.run(table.createIndex(col_hashKey, ifNotExists: true))
            try db.run(table.createIndex(col_pinnedDate, ifNotExists: true))
            try db.run(table.createIndex(col_kind, ifNotExists: true))
            if Int(db.userVersion ?? 0) < Int(Self.schemaVersion) {
                try backfillKindCodes(on: db)
                db.userVersion = Self.schemaVersion
                Log("Migrated: backfilled kindCode, user_version=\(Self.schemaVersion)")
            }
            Log("Create Table Success")
        } catch {
            Log("Create Table Error: \(error)")
        }
    }

    /// 按实际表结构补齐后加的列。不依赖 user_version，
    /// 版本号已推进但缺列的库（旧版「清空所有数据」DROP 重建后缺 kindCode）也能补回。
    private func addMissingColumns(on db: Connection) throws {
        var existing = Set<String>()
        for row in try db.prepare("PRAGMA table_info(\(Self.tableName))") {
            if let name = row[1] as? String { existing.insert(name) }
        }
        let columns: [(name: String, sql: String)] = [
            ("ocrText", table.addColumn(col_ocrText)),
            ("imgW", table.addColumn(col_imgW)),
            ("imgH", table.addColumn(col_imgH)),
            ("pinnedDate", table.addColumn(col_pinnedDate)),
            ("kindCode", table.addColumn(col_kind)),
        ]
        for column in columns where !existing.contains(column.name) {
            try db.run(column.sql)
            Log("Migrated: added \(column.name) column")
        }
    }

    /// 按当前规则重算文本行的派生类型并回写 kindCode，只更新结果有变化的行
    private func backfillKindCodes(on db: Connection) throws {
        let textTypes = [PasteboardType.rtf, .rtfd, .string].map(\.rawValue)
        let query = table.select(col_id, col_type, col_dataString, col_kind)
            .filter(makeTypeFilter(textTypes))
        let rows = try Array(db.prepare(query))
        try db.transaction {
            for row in rows {
                let kind = PasteboardModel.derivedType(
                    forText: row[col_dataString],
                    type: PasteboardType(row[col_type])
                )
                guard row[col_kind] != kind?.rawValue else { continue }
                _ = try db.run(table.filter(col_id == row[col_id]).update(col_kind <- kind?.rawValue))
            }
        }
    }
}

// MARK: - 对外接口

extension PasteSQLManager {
    var totalCount: Int {
        countRows(filter: nil)
    }

    var databaseSize: Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: dbPath),
              let fileSize = attributes[.size] as? Int else { return 0 }
        return fileSize
    }

    func countRows(filter: Expression<Bool>?) -> Int {
        do {
            var query = table
            if let f = filter { query = query.filter(f) }
            return try db?.scalar(query.count) ?? 0
        } catch {
            Log("获取总数失败：\(error)")
            return 0
        }
    }

    /// 顶栏分段按钮上显示的各类型条数。
    /// 文本条数与「文本」筛选结果保持一致(含颜色/链接);颜色、链接按 kind 标签直接统计。
    func typeCounts() -> TypeCounts {
        let textTypes = [PasteboardType.rtf, .rtfd, .string].map(\.rawValue)
        let imageTypes = [PasteboardType.png, .tiff].map(\.rawValue)
        var derived: [PasteModelType: Int] = [:]
        do {
            let query = table.select(col_kind, col_kind.count).filter(col_kind != nil).group(col_kind)
            for row in try db?.prepare(query) ?? AnySequence([]) {
                if let raw = row[col_kind], let type = PasteModelType(rawValue: raw) {
                    derived[type] = row[col_kind.count]
                }
            }
        } catch {
            Log("统计派生类型条数失败：\(error)")
        }
        return TypeCounts(
            text: countRows(filter: makeTypeFilter(textTypes)),
            image: countRows(filter: makeTypeFilter(imageTypes)),
            derived: derived
        )
    }

    /// 插入一条记录，同 hashKey 的旧行会被替换。删旧行和插新行放在同一事务里，插入失败时旧行不丢。
    /// - Returns: 是否写入成功
    @discardableResult
    func insert(item: PasteboardModel) -> Bool {
        guard let db else { return false }
        do {
            try db.transaction {
                // 重新捕获相同内容时先删旧行再插新行;旧行若已置顶则继承置顶状态,
                // 否则去重一旦命中,用户的置顶项会被无置顶的新行顶掉。
                var pinnedDate = item.pinnedDate
                if let oldRow = try db.pluck(
                    table.filter(col_hashKey == item.hashValue).select(col_pinnedDate)
                ), let oldPinnedDate = try oldRow.get(col_pinnedDate) {
                    pinnedDate = oldPinnedDate
                }

                try db.run(table.filter(col_hashKey == item.hashValue).delete())

                let insertQuery = table.insert(
                    col_hashKey <- item.hashValue,
                    col_type <- item.pasteboardType.rawValue,
                    col_data <- item.data,
                    col_showData <- item.showData,
                    col_date <- item.date,
                    col_appPath <- item.appPath,
                    col_appName <- item.appName,
                    col_dataString <- item.dataString,
                    col_length <- item.length,
                    col_ocrText <- item.ocrText,
                    col_imgW <- item.imageWidth,
                    col_imgH <- item.imageHeight,
                    col_pinnedDate <- pinnedDate,
                    col_kind <- item.derivedType?.rawValue
                )
                let rowId = try db.run(insertQuery)
                Log("插入成功：\(rowId)")
            }
            return true
        } catch {
            Log("插入失败：\(error)")
            return false
        }
    }

    func delete(filter: Expression<Bool>) {
        let query = table.filter(filter)
        do {
            let count = try db?.run(query.delete())
            Log("删除的条数为：\(String(describing: count))")
        } catch {
            Log("删除失败：\(error)")
        }
    }

    func deleteByHash(_ hashValue: Int) {
        delete(filter: col_hashKey == hashValue)
    }

    /// 按 hash 回写图片的 OCR 文本(识别异步完成后调用)
    func updateOCRText(_ text: String, forHash hashValue: Int) {
        let query = table.filter(col_hashKey == hashValue)
        do {
            let count = try db?.run(query.update(col_ocrText <- text))
            Log("更新 OCR 文本的条数为：\(String(describing: count))")
        } catch {
            Log("更新 OCR 文本失败：\(error)")
        }
    }

    /// 按 hash 回写置顶状态。置顶传 Date(),取消置顶传 nil。
    func updatePinned(_ date: Date?, forHash hashValue: Int) {
        let query = table.filter(col_hashKey == hashValue)
        do {
            let count = try db?.run(query.update(col_pinnedDate <- date))
            Log("更新置顶状态的条数为：\(String(describing: count))")
        } catch {
            Log("更新置顶状态失败：\(error)")
        }
    }

    // MARK: - 图片外置文件清理支持

    func deleteBeforeDate(_ deadline: Date) {
        // 置顶项豁免自动过期清理
        // 置顶项(pinnedDate 非空)豁免过期清理;IS NULL 结果为 Bool?,?? false 收敛为 Bool
        delete(filter: col_date < deadline && ((col_pinnedDate === Date?.none) ?? false))
    }

    /// 查询某日期之前的图片行 hash(用于删除前先取得待清理的外置文件名)。置顶项豁免。
    func imageHashesBeforeDate(_ deadline: Date) -> [Int] {
        let imageTypes = [PasteboardType.png.rawValue, PasteboardType.tiff.rawValue]
        let typeFilter = imageTypes.dropFirst().reduce(col_type == imageTypes[0]) { $0 || col_type == $1 }
        let query = table.select(col_hashKey).filter(col_date < deadline && typeFilter && ((col_pinnedDate === Date?.none) ?? false))
        do {
            guard let rows = try db?.prepare(query) else { return [] }
            return rows.compactMap { try? $0.get(col_hashKey) }
        } catch {
            Log("查询待清理图片 hash 失败：\(error)")
            return []
        }
    }

    /// 清空所有数据。用 DELETE 而不是 DROP 重建，保留表结构和索引。
    func clearAllData() {
        guard let db else { return }
        do {
            let removed = try db.run(table.delete())
            Log("删除所有数据：\(removed) 行")
        } catch {
            Log("删除失败：\(error)")
            return
        }
        vacuum()
    }

    /// 整理数据库文件，把删除留下的空闲页真正还给磁盘。
    /// SQLite 删除只把页标记为空闲(freelist)、不缩小文件；VACUUM 重写整个文件挤掉空洞。
    /// 开销较大(全程持写锁、重写文件)，只在低频时机调用(如每日过期清理后)。
    func vacuum() {
        do {
            try db?.execute("VACUUM")
            Log("VACUUM 完成")
        } catch {
            Log("VACUUM 失败：\(error)")
        }
    }

    func distinctApps(limit count: Int = 5) -> [(name: String, path: String)] {
        do {
            let cnt = col_appName.count
            let query = table
                .select(col_appName, col_appPath, cnt)
                .group(col_appName)
                .order(cnt.desc)
                .limit(count)
            guard let rows = try db?.prepare(query) else { return [] }
            return rows.compactMap { row in
                guard let name = try? row.get(col_appName),
                      let path = try? row.get(col_appPath) else { return nil }
                return (name: name, path: path)
            }
        } catch {
            Log("查询应用列表失败：\(error)")
            return []
        }
    }

    func allDistinctApps() -> [(name: String, path: String)] {
        distinctApps(limit: 1000)
    }

    /// 搜索并直接返回 [PasteboardModel]，Row 解析在 actor 内完成
    func search(filter: Expression<Bool>? = nil, limit: Int? = nil, offset: Int? = nil) -> [PasteboardModel] {
        guard !Task.isCancelled else {
            Log("Task is cancelled")
            return []
        }
        var query = table
            .select(rowid, col_id, col_hashKey, col_type, col_data, col_date, col_appPath, col_appName, col_dataString, col_showData, col_length, col_ocrText, col_imgW, col_imgH, col_pinnedDate)
            // 置顶项恒在前(pinnedDate 非空且倒序,NULL 在 DESC 下自动垫底),组内再按 date 倒序
            .order(col_pinnedDate.desc, col_date.desc)
        if let f = filter {
            query = query.filter(f)
        }
        if let l = limit {
            if let o = offset {
                query = query.limit(l, offset: o)
            } else {
                query = query.limit(l)
            }
        }

        do {
            guard let result = try db?.prepare(query) else { return [] }
            return result.compactMap { row in
                guard let typeStr = try? row.get(col_type),
                      let data = try? row.get(col_data),
                      let hashV = try? row.get(col_hashKey),
                      let date = try? row.get(col_date) else { return nil }
                return PasteboardModel(
                    pasteboardType: PasteboardType(typeStr),
                    data: data,
                    showData: (try? row.get(col_showData) ?? data) ?? data,
                    hashValue: hashV,
                    date: date,
                    appPath: (try? row.get(col_appPath)) ?? "",
                    appName: (try? row.get(col_appName)) ?? "",
                    dataString: (try? row.get(col_dataString)) ?? "",
                    length: (try? row.get(col_length)) ?? 0,
                    ocrText: (try? row.get(col_ocrText)) ?? nil,
                    imageWidth: (try? row.get(col_imgW)) ?? nil,
                    imageHeight: (try? row.get(col_imgH)) ?? nil,
                    pinnedDate: (try? row.get(col_pinnedDate)) ?? nil
                )
            }
        } catch {
            Log("查询失败：\(error)")
            return []
        }
    }

    // MARK: - Private Filter Builders

    /// 转义 LIKE 模式里的 % 和 _,使其按字面匹配。顺序要点:先转义 `\` 本身再转义 % 和 _。
    /// 配合 like(escape: "\\") 使用。
    private func escapeLikePattern(_ keyword: String) -> String {
        keyword
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func makeSearchFilter(keyword: String) -> Expression<Bool> {
        // 关键字匹配 应用名 / 文本内容 / 图片 OCR 文本(让图里的字也能被搜到)
        let pattern = "%\(escapeLikePattern(keyword))%"
        return col_appName.like(pattern, escape: "\\")
            || col_dataString.like(pattern, escape: "\\")
            || (col_ocrText ?? "").like(pattern, escape: "\\")
    }

    private func makeAppFilter(_ app: String) -> Expression<Bool> {
        col_appName == app
    }

    private func makeTypeFilter(_ types: [String]) -> Expression<Bool> {
        types.dropFirst().reduce(col_type == types[0]) { $0 || col_type == $1 }
    }

    private func makeDateRangeFilter(start: Date, end: Date) -> Expression<Bool> {
        col_date >= start && col_date < end
    }

    /// 组合搜索：接受 Sendable 参数，内部构建 filter 并执行搜索
    func searchWithParams(keyword: String, state: FilterState, limit: Int?, offset: Int?) -> [PasteboardModel] {
        let filter = buildFilterInternal(keyword: keyword, state: state)
        return search(filter: filter, limit: limit, offset: offset)
    }

    private func buildFilterInternal(keyword: String, state: FilterState) -> Expression<Bool>? {
        var conditions: [Expression<Bool>] = []

        if !keyword.isEmpty {
            conditions.append(makeSearchFilter(keyword: keyword))
        }
        if let app = state.selectedApp {
            conditions.append(makeAppFilter(app))
        }
        if let selectedType = state.selectedType {
            switch selectedType {
            case .string:
                conditions.append(makeTypeFilter([PasteboardType.rtf.rawValue, PasteboardType.rtfd.rawValue, PasteboardType.string.rawValue]))
            case .image:
                conditions.append(makeTypeFilter([PasteboardType.png.rawValue, PasteboardType.tiff.rawValue]))
            case .none:
                break
            default:
                // 颜色/链接等派生类型按 kind 标签筛选
                conditions.append((col_kind == selectedType.rawValue) ?? false)
            }
        }
        if let dateRange = state.selectedDateRange {
            let interval = dateRange.dateInterval
            conditions.append(makeDateRangeFilter(start: interval.start, end: interval.end))
        }

        guard !conditions.isEmpty else { return nil }
        return conditions.dropFirst().reduce(conditions[0]) { $0 && $1 }
    }
}
