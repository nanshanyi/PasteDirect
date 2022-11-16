//
//  PasteDataStore.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Foundation
import AppKit
import SQLite

let mainDataStore = PasteDataStore()

class PasteDataStore {
    
    private var sqlManager = PasteSQLManager.manager
    var dataList:[PasteboardModel] = []
    var totoalCount: Int = 0
    var pageIndex = 1
    let pageSize = 50
    var dataChange = false
    
    init() {
        dataList = getData(limit: pageIndex * pageSize)
        totoalCount = sqlManager.totoalCount()
    }
    
    func addNewItem(item: NSPasteboardItem) {
        guard let model = PasteboardModel.model(with: item) else { return }
        sqlManager.insert(item: model)
        updateTotoalCount()
        dataChange = true
        dataList.removeAll(where: { $0.hashValue == model.hashValue })
        dataList.insert(model, at: 0)
    }
    
    func deleteItem(item: PasteboardModel) {
        deleteItems(filter: hashKey == item.hashValue )
    }
    
    func loadMoreData() -> [PasteboardModel] {
        if dataList.count >= pageSize * pageIndex {
            pageIndex += 1
            dataList = getData(limit: pageIndex * pageSize)
        }
        return dataList
    }
    
    func getData(limit: Int = 50) -> [PasteboardModel] {
        let rows = sqlManager.search(limit:limit)
        return getItems(rows: rows)
    }
    
    func searchData(_ keyWord: String) -> [PasteboardModel] {
        let rows = sqlManager.search(filter: appName.like("%\(keyWord)%") || dataString.like("%\(keyWord)%"))
        return getItems(rows: rows)
    }
    
    func getItems(rows:[Row]) -> [PasteboardModel] {
        var item: PasteboardModel
        var items = [PasteboardModel]()
        for row in rows {
            if let type = try? row.get(type),
               let data = try? row.get(data),
               let hashV = try? row.get(hashKey),
               let date = try? row.get(date) {
                let appName = try? row.get(appName)
                let appPath = try? row.get(appPath)
                let dataString = try? row.get(dataString)
                item = PasteboardModel(pasteBoardType: PasteboardModel.PasteboardType(rawValue: type)!, data: data, hashValue: hashV, date:date, appPath: appPath ?? "", appName: appName ?? "")
                item.dataString = dataString ?? ""
                items.append(item)
            }
        }
        return items
    }
    
    func clearData(_ type: HistoryTime) {
        
        var dateCom = DateComponents()
        switch type {
        case .day:
            dateCom = DateComponents(calendar: NSCalendar.current, day: -1)
        case .week:
            dateCom = DateComponents(calendar: NSCalendar.current, day: -7)
        case .month:
            dateCom = DateComponents(calendar: NSCalendar.current, month: -1)
        default:
            return
        }
        if let deadDate = NSCalendar.current.date(byAdding: dateCom, to: Date()) {
            dataList.removeAll(where: { $0.date < deadDate })
            deleteItems(filter: date < deadDate)
        }
    }
    
    func clearAllData() {
        dataList.removeAll()
        sqlManager.dropTable()
    }
    
    func updateTotoalCount() {
        totoalCount = sqlManager.totoalCount()
    }
    
    func deleteItems(filter:Expression<Bool>) {
        sqlManager.delete(filter: filter)
        updateTotoalCount()
    }
    
}



