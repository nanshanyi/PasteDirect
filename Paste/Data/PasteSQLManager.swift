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
let date = Expression<Date>("date")
let appPath = Expression<String>("appPath")
let appName = Expression<String>("appName")
let dataString = Expression<String>("dataString")



class PasteSQLManager: NSObject {
    static let manager = PasteSQLManager()
    private lazy var db: Connection = {
        
        let path = NSSearchPathForDirectoriesInDomains(
                        .documentDirectory, .userDomainMask, true
        ).first!.appending("/paste")
        var isDir = ObjCBool(false)
        let filExist = FileManager.default.fileExists(atPath: path, isDirectory:&isDir)
        if !filExist || !isDir.boolValue {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            } catch {
                print(error)
            }
        }
            
        let db = try! Connection("\(path)/paste.sqlite3")
        db.busyTimeout = 5.0
        return db
    }()
    private lazy var table: Table = {
        let tab = Table("pasteContent")
        try! db.run(tab.create(ifNotExists: true, withoutRowid: false, block: { t in
            t.column(id, primaryKey: true)
            t.column(hashKey)
            t.column(type)
            t.column(data)
            t.column(date)
            t.column(appPath)
            t.column(appName)
            t.column(dataString)
        }))
        return tab
    }()
    
    func totoalCount() -> Int {
        if let count = try? db.scalar(table.count) {
            return count
        }
        return 0
    }
    //增
    func insert(item: PasteboardModel) {
        
        let query = table
        delete(filter: hashKey == item.hashValue)
        let insert = query.insert(hashKey <- item.hashValue, type <- item.pasteBoardType.rawValue, data <- item.data, date <- item.date, appPath <- item.appPath, appName <- item.appName, dataString <- item.dataString)
        if let rowId = try? db.run(insert) {
            print("插入成功：\(rowId)")
        } else {
            print("插入失败")
        }
        
    }
    
    //删单条
    func delete(hash h: Int) {
        delete(filter: hashKey == h )
    }
    
    //根据条件删除
    func delete(filter: Expression<Bool>? = nil) {
        
        var query = table
        
        if let f = filter {
            query = query.filter(f)
        }
        if let count = try? db.run(query.delete()) {
            print("删除的条数为：\(count)")
        } else {
            print("删除失败")
        }
        
    }
    
//    //改
//    func update(id: Int64, item: PasteboardModel) {
//        guard var query = table else { return }
//        let update = getTable().filter(rowid == id)
//        if let count = try? getDB().run(update.update(value_column <- item["value"].doubleValue, tag_column <- item["tag"].stringValue , detail_column <- item["detail"].stringValue)) {
//            print("修改的结果为：\(count == 1)")
//        } else {
//            print("修改失败")
//        }
//
//    }
    
    //查
    func search(filter: Expression<Bool>? = nil, select: [Expressible] = [rowid, id, hashKey, type, data, date, appPath, appName, dataString], order: [Expressible] = [date.desc], limit: Int? = nil, offset: Int? = nil) -> [Row] {
        var query = table.select(select).order(order)
        if let f = filter {
            query = query.filter(f)
        }
        if let l = limit {
            if let o = offset{
                query = query.limit(l, offset: o)
            }else {
                query = query.limit(l)
            }
        }
        if let result = try? db.prepare(query) {
            return Array(result)
        }
        return []
    }
    
}

