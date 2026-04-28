//
//  PasteSQLManager.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/1.
//

import Foundation
@preconcurrency import SQLite

typealias Expression = SQLite.Expression

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

    // MARK: - DB

    private let dbPath: String
    private var db: Connection?
    private var table: Table

    init() {
        let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first!.appending("/paste/paste.sqlite3")
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
        self.table = Table("pasteContent")
    }

    /// 初始化表结构，需在首次使用前调用
    func setup() {
        createTable()
    }

    private func createTable() {
        do {
            try db?.run(table.create(ifNotExists: true, withoutRowid: false) { [col_id, col_hashKey, col_type, col_data, col_showData, col_date, col_appPath, col_appName, col_dataString, col_length] t in
                t.column(col_id, primaryKey: true)
                t.column(col_hashKey); t.column(col_type); t.column(col_data)
                t.column(col_showData); t.column(col_date); t.column(col_appPath)
                t.column(col_appName); t.column(col_dataString); t.column(col_length)
            })
            try db?.run(table.createIndex(col_date, ifNotExists: true))
            try db?.run(table.createIndex(col_appName, ifNotExists: true))
            try db?.run(table.createIndex(col_type, ifNotExists: true))
            try db?.run(table.createIndex(col_hashKey, ifNotExists: true))
            Log("Create Table Success")
        } catch {
            Log("Create Table Error: \(error)")
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

    func insert(item: PasteboardModel) {
        // 先删除同 hash 的旧记录
        let deleteQuery = table.filter(col_hashKey == item.hashValue)
        _ = try? db?.run(deleteQuery.delete())

        let insertQuery = table.insert(
            col_hashKey <- item.hashValue,
            col_type <- item.pasteboardType.rawValue,
            col_data <- item.data,
            col_showData <- item.showData,
            col_date <- item.date,
            col_appPath <- item.appPath,
            col_appName <- item.appName,
            col_dataString <- item.dataString,
            col_length <- item.length
        )
        do {
            let rowId = try db?.run(insertQuery)
            Log("插入成功：\(String(describing: rowId))")
        } catch {
            Log("插入失败：\(error)")
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

    func deleteBeforeDate(_ deadline: Date) {
        delete(filter: col_date < deadline)
    }

    func clearAllData() {
        do {
            _ = try db?.run(table.drop())
            try db?.execute("VACUUM")
            createTable()
            Log("删除所有数据")
        } catch {
            Log("删除失败：\(error)")
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
            .select(rowid, col_id, col_hashKey, col_type, col_data, col_date, col_appPath, col_appName, col_dataString, col_showData, col_length)
            .order(col_date.desc)
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
                    length: (try? row.get(col_length)) ?? 0
                )
            }
        } catch {
            Log("查询失败：\(error)")
            return []
        }
    }

    // MARK: - Private Filter Builders

    private func makeSearchFilter(keyword: String) -> Expression<Bool> {
        col_appName.like("%\(keyword)%") || col_dataString.like("%\(keyword)%")
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
            case .color:
                conditions.append(makeTypeFilter([PasteboardType.rtf.rawValue, PasteboardType.rtfd.rawValue, PasteboardType.string.rawValue]))
            case .none:
                break
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
