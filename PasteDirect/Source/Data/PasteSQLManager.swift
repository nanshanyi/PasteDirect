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

/// 分页游标：上一页最后一行的排序键 (pinnedDate, date, id)。由 PasteSQLManager 生成，外部只透传。
struct PageCursor: Sendable, Equatable {
    fileprivate let pinnedKey: String
    fileprivate let dateKey: String
    fileprivate let id: Int
}

/// 列表查询里置顶项的取舍
enum PinScope: Sendable {
    /// 置顶项和其他项一起，置顶在前
    case all
    /// 只要未置顶的（置顶项收在折叠条里时的默认列表）
    case excluded
    /// 只要置顶的
    case only
}

struct PastePage: Sendable {
    let items: [PasteboardModel]
    /// 本页最后一行的游标，空页为 nil
    let cursor: PageCursor?
    /// 是否可能还有下一页（本页取满了 limit）
    let hasMore: Bool
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

}

// MARK: - 表结构与迁移

extension PasteSQLManager {
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
            try ensureUniqueHashKey(on: db)
            // 单列 pinnedDate 索引已被下面的 (pinnedDate, date) 复合索引覆盖，老库里的删掉，免得每次写入多维护一个
            try db.run(table.dropIndex(col_pinnedDate, ifExists: true))
            try db.run(table.createIndex(col_kind, ifNotExists: true))
            // 列表排序 (pinnedDate DESC, date DESC, id DESC) 按这个索引顺序读，不用扫全表再临时排序（id 是 rowid，索引里自带）。
            // 游标条件里的 COALESCE(pinnedDate, '') 不是裸列，没法用索引定位到游标处：翻页仍从索引开头扫过已加载的那些项，
            // 但只读索引、命中后才回表，开销随已加载条数增长，不随表大小增长
            try db.run(table.createIndex(col_pinnedDate, col_date, ifNotExists: true))
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

    /// 保证 hashKey 上是唯一索引（insert 的 upsert 依赖它）。按实际索引状态检查，不依赖 user_version：
    /// 旧库只有普通索引，或旧版本重建过表时，先合并重复行再建唯一索引。
    private func ensureUniqueHashKey(on db: Connection) throws {
        // SQLite.swift 生成索引名时会去掉引号并整体转小写（实际是 index_pastecontent_on_hashkey），
        // 这里按同样规则拼期望名，否则永远判不出「已有唯一索引」，每次启动都会重跑一遍合并。
        let expectedIndex = "index_\(Self.tableName)_on_hashKey".lowercased()
        for row in try db.prepare("PRAGMA index_list(\(Self.tableName))") {
            let name = (row[1] as? String)?.lowercased()
            if name == expectedIndex, row[2] as? Int64 == 1 { return }
        }
        try db.transaction {
            // 同一内容有多行时保留 id 最大的一行；任一行置顶过，保留行继承最晚的置顶时间。
            // 只处理有重复的 hashKey，没有重复时这一步不写任何行
            try db.run("""
                UPDATE \(Self.tableName) SET pinnedDate = (
                    SELECT MAX(p.pinnedDate) FROM \(Self.tableName) p WHERE p.hashKey = \(Self.tableName).hashKey
                ) WHERE pinnedDate IS NULL AND hashKey IN (
                    SELECT hashKey FROM \(Self.tableName) GROUP BY hashKey HAVING COUNT(*) > 1
                )
                """)
            try db.run("""
                DELETE FROM \(Self.tableName)
                WHERE id NOT IN (SELECT MAX(id) FROM \(Self.tableName) GROUP BY hashKey)
                """)
            let removed = db.changes
            try db.run(table.dropIndex(col_hashKey, ifExists: true))
            try db.run(table.createIndex(col_hashKey, unique: true, ifNotExists: true))
            Log("Migrated: unique hashKey index, removed \(removed) duplicate rows")
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

// MARK: - 查询与分页

extension PasteSQLManager {
    /// 取 cursor 之后的一页；cursor 为 nil 时取第一页
    func fetchPage(keyword: String = "", state: FilterState = .empty, pins: PinScope = .all, after cursor: PageCursor? = nil, limit: Int) -> PastePage {
        var conditions = [buildFilterInternal(keyword: keyword, state: state), pinFilter(pins)].compactMap { $0 }
        if let cursor { conditions.append(cursorFilter("<", cursor)) }
        return query(filter: combine(conditions), limit: limit)
    }

    /// 重新取从第一条到 cursor（含）为止的所有行，用于数据变化后原地刷新已加载的范围。
    /// cursor 为 nil 时取全部匹配行。
    func fetchThrough(keyword: String, state: FilterState, pins: PinScope = .all, cursor: PageCursor?) -> [PasteboardModel] {
        var conditions = [buildFilterInternal(keyword: keyword, state: state), pinFilter(pins)].compactMap { $0 }
        if let cursor { conditions.append(cursorFilter(">=", cursor)) }
        return query(filter: combine(conditions), limit: nil).items
    }

    /// 列表查询。排序：置顶在前（pinnedDate 倒序），其余按 date 倒序，id 倒序兜底保证顺序唯一。
    /// Row 解析在 actor 内完成，顺带用最后一行生成下一页的游标。
    private func query(filter: Expression<Bool>?, limit: Int?) -> PastePage {
        guard !Task.isCancelled else {
            Log("Task is cancelled")
            return PastePage(items: [], cursor: nil, hasMore: false)
        }
        var query = table
            .select(col_id, col_hashKey, col_type, col_data, col_date, col_appPath, col_appName, col_dataString, col_showData, col_length, col_ocrText, col_imgW, col_imgH, col_pinnedDate)
            // NULL 在 DESC 下垫底，未置顶项自然排在置顶项之后
            .order(col_pinnedDate.desc, col_date.desc, col_id.desc)
        if let filter {
            query = query.filter(filter)
        }
        if let limit {
            query = query.limit(limit)
        }

        do {
            guard let rows = try db?.prepare(query) else { return PastePage(items: [], cursor: nil, hasMore: false) }
            var items: [PasteboardModel] = []
            var cursor: PageCursor?
            var rowCount = 0
            for row in rows {
                rowCount += 1
                // 游标只依赖排序键，先于其他字段生成：某行内容解码失败被跳过时，下一页也照样从它之后查
                guard let id = try? row.get(col_id),
                      let date = try? row.get(col_date) else { continue }
                let pinnedDate = (try? row.get(col_pinnedDate)) ?? nil
                cursor = PageCursor(pinnedKey: pinnedDate?.datatypeValue ?? "", dateKey: date.datatypeValue, id: id)
                guard let typeStr = try? row.get(col_type),
                      let data = try? row.get(col_data),
                      let hashV = try? row.get(col_hashKey) else { continue }
                items.append(PasteboardModel(
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
                    pinnedDate: pinnedDate
                ))
            }
            // 一整页都没生成游标时下一页无从查起，必须停，否则会用同一个游标反复取同一页
            let hasMore = cursor != nil && (limit.map { rowCount >= $0 } ?? false)
            return PastePage(items: items, cursor: cursor, hasMore: hasMore)
        } catch {
            Log("查询失败：\(error)")
            return PastePage(items: [], cursor: nil, hasMore: false)
        }
    }

    /// 排序键与游标比较。排序键是 (COALESCE(pinnedDate, ''), date, id)：
    /// 日期按 SQLite.swift 的定长文本存储，可直接比大小；未置顶记作 ''，比任何日期都小，与 NULL 垫底一致。
    private func cursorFilter(_ op: String, _ cursor: PageCursor) -> Expression<Bool> {
        Expression<Bool>(
            "(COALESCE(\"pinnedDate\", ''), \"date\", \"id\") \(op) (?, ?, ?)",
            [cursor.pinnedKey, cursor.dateKey, Int64(cursor.id)]
        )
    }

    /// 排除置顶时剩下的行置顶键都是 ''，游标比较照常成立，翻页不受影响
    private func pinFilter(_ pins: PinScope) -> Expression<Bool>? {
        switch pins {
        case .all: return nil
        case .excluded: return (col_pinnedDate === Date?.none) ?? false
        case .only: return (col_pinnedDate !== Date?.none) ?? false
        }
    }

    private func combine(_ conditions: [Expression<Bool>]) -> Expression<Bool>? {
        guard let first = conditions.first else { return nil }
        return conditions.dropFirst().reduce(first) { $0 && $1 }
    }
}

// MARK: - 筛选条件

extension PasteSQLManager {
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

        return combine(conditions)
    }

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
}

// MARK: - 统计

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
}

// MARK: - 写入

extension PasteSQLManager {
    /// 插入一条记录。同 hashKey 已存在时原地更新这一行（依赖 hashKey 唯一索引）；
    /// 旧行已置顶则保留置顶时间，否则去重会把用户的置顶顶掉。
    /// - Returns: 是否写入成功
    @discardableResult
    func insert(item: PasteboardModel) -> Bool {
        guard let db else { return false }
        let values: [Setter] = [
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
            col_pinnedDate <- item.pinnedDate,
            col_kind <- item.derivedType?.rawValue,
        ]
        let keepPinned = Expression<Date?>(literal: "COALESCE(\"pinnedDate\", \"excluded\".\"pinnedDate\")")
        let updates: [Setter] = [
            excluded(col_type), excluded(col_data), excluded(col_showData), excluded(col_date),
            excluded(col_appPath), excluded(col_appName), excluded(col_dataString), excluded(col_length),
            excluded(col_ocrText), excluded(col_imgW), excluded(col_imgH), excluded(col_kind),
            col_pinnedDate <- keepPinned,
        ]
        do {
            try db.run(table.upsert(values, onConflictOf: col_hashKey, set: updates))
            Log("插入成功：\(item.hashValue)")
            return true
        } catch {
            Log("插入失败：\(error)")
            return false
        }
    }

    /// upsert 冲突时取本次要插入的值：`列 = excluded.列`
    private func excluded<V: Value>(_ column: Expression<V>) -> Setter {
        column <- Expression<V>(literal: "\"excluded\".\(column.template)")
    }

    private func excluded<V: Value>(_ column: Expression<V?>) -> Setter {
        column <- Expression<V?>(literal: "\"excluded\".\(column.template)")
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
}

// MARK: - 删除与清理

extension PasteSQLManager {
    /// - Returns: 删除的行数
    @discardableResult
    func delete(filter: Expression<Bool>) -> Int {
        let query = table.filter(filter)
        do {
            let count = try db?.run(query.delete()) ?? 0
            Log("删除的条数为：\(count)")
            return count
        } catch {
            Log("删除失败：\(error)")
            return 0
        }
    }

    func deleteByHash(_ hashValue: Int) {
        delete(filter: col_hashKey == hashValue)
    }

    /// - Returns: 删除的行数
    @discardableResult
    func deleteBeforeDate(_ deadline: Date) -> Int {
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
}
