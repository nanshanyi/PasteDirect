//
//  PasteSQLManager.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/1.
//

import Foundation
import SQLite

let id = Expression<Int>("id")
let hashKey = Expression<Int>("hashKey")
let type = Expression<Int>("type")
let data = Expression<Data>("data")
let showData = Expression<Data?>("showData")
let date = Expression<Date>("date")
let appPath = Expression<String>("appPath")
let appName = Expression<String>("appName")
let dataString = Expression<String>("dataString")
let length = Expression<Int>("length")

final class PasteSQLManager: NSObject {
    static let manager = PasteSQLManager()

    private lazy var db: Connection? = {
        let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first!.appending("/paste")
        var isDir = ObjCBool(false)
        let filExist = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if !filExist || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            } catch {
                Log(error.localizedDescription)
            }
        }
        do {
            let db = try Connection("\(path)/paste.sqlite3")
            db.busyTimeout = 5.0
            return db
        } catch {
            Log("Connection Error\(error)")
        }
        return nil
    }()

    private lazy var table: Table = {
        let tab = Table("pasteContent")
        let stateMent = tab.create(ifNotExists: true, withoutRowid: false) { t in
            t.column(id, primaryKey: true)
            t.column(hashKey)
            t.column(type)
            t.column(data)
            t.column(showData)
            t.column(date)
            t.column(appPath)
            t.column(appName)
            t.column(dataString)
            t.column(length)
        }
        do {
            try db?.run(stateMent)
        } catch {
            Log("Create Table Error: \(error)")
        }
        return tab
    }()
}

// MARK: - 数据库操作 对外接口

extension PasteSQLManager {
    var totoalCount: Int {
        do {
            return try db?.scalar(table.count) ?? 0
        } catch {
            Log("获取总数失败：\(error)")
            return 0
        }
    }

    // 增
    func insert(item: PasteboardModel) async {
        let query = table
        await delete(filter: hashKey == item.hashValue)
        let insert = query.insert(
            hashKey <- item.hashValue,
            type <- item.pasteBoardType.rawValue,
            data <- item.data,
            showData <- item.showData,
            date <- item.date,
            appPath <- item.appPath,
            appName <- item.appName,
            dataString <- item.dataString,
            length <- item.length
        )
        do {
            let rowId = try db?.run(insert)
            Log("插入成功：\(String(describing: rowId))")
        } catch {
            Log("插入失败：\(error)")
        }
    }

    // 根据条件删除
    func delete(filter: Expression<Bool>) async {
        let query = table.filter(filter)
        do {
            let count = try db?.run(query.delete())
            Log("删除的条数为：\(String(describing: count))")
        } catch {
            Log("删除失败：\(error)")
        }
    }

    func dropTable() {
        do {
           let d = try db?.run(table.drop())
            Log("删除所有\(String(describing: d?.columnCount))")
        } catch {
            Log("删除失败：\(error)")
        }
    }

//    //改
//    func update(id: Int64, item: PasteboardModel) {
//        guard var query = table else { return }
//        let update = getTable().filter(rowid == id)
//        if let count = try? getDB().run(update.update(value_column <- item["value"].doubleValue, tag_column <- item["tag"].stringValue , detail_column <- item["detail"].stringValue)) {
//            Log("修改的结果为：\(count == 1)")
//        } else {
//            Log("修改失败")
//        }
//
//    }

    // 查
    func search(filter: Expression<Bool>? = nil, select: [Expressible] = [rowid, id, hashKey, type, data, date, appPath, appName, dataString, showData, length], order: [Expressible] = [date.desc], limit: Int? = nil, offset: Int? = nil) async -> [Row] {
        guard !Task.isCancelled else {
            Log("Task is cancelled")
            return []
        }
        var query = table.select(select).order(order)
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
            if let result = try db?.prepare(query) {
                return Array(result)
            }
            return []
        } catch {
            Log("查询失败：\(error)")
            return []
        }
    }
}
