//
//  PasteDataStore.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Foundation
import AppKit
import SQLite
import UIColorHexSwift

let mainDataStore = PasteDataStore()

class PasteDataStore {
    
    private var sqlManager = PasteSQLManager.manager
    private var userDefault = UserDefaults.standard
    private var colorDic = Dictionary<String, String>()
    var dataList:[PasteboardModel] = []
    var totoalCount: Int = 0
    var pageIndex = 1
    let pageSize = 50
    var dataChange = false
    
    init() {
        dataList = getData(limit: pageIndex * pageSize)
        totoalCount = sqlManager.totoalCount()
        if let dic = userDefault.dictionary(forKey: PrefKey.appColorData.rawValue) as? [String : String] {
            colorDic = dic
        }
    }
    
    func addNewItem(item: NSPasteboardItem) {
        guard let model = PasteboardModel.model(with: item) else { return }
        sqlManager.insert(item: model)
        updateTotoalCount()
        dataChange = true
        dataList.removeAll(where: { $0.hashValue == model.hashValue })
        dataList.insert(model, at: 0)
        updateColor(model);
    }
    
    func addOldModel(_ model: PasteboardModel) {
        sqlManager.insert(item: model)
        updateTotoalCount()
        dataChange = true
        dataList.removeAll(where: { $0.hashValue == model.hashValue })
        dataList.insert(model, at: 0)
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
    
    func updateTotoalCount() {
        totoalCount = sqlManager.totoalCount()
    }
    
}
//MARK: - dataManager
extension PasteDataStore {
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
    
    func deleteItem(item: PasteboardModel) {
        dataList.removeAll(where: { $0.hashValue == item.hashValue })
        deleteItems(filter: hashKey == item.hashValue )
    }
    
    func deleteItems(filter:Expression<Bool>) {
        sqlManager.delete(filter: filter)
        updateTotoalCount()
    }
    
    func clearExpiredData() {
        let current = userDefault.integer(forKey: PrefKey.historyTime.rawValue)
        guard let type = HistoryTime(rawValue: current) else { return }
        clearData(type);
    }
}

extension PasteDataStore {
    func updateColor(_ model: PasteboardModel) {
        DispatchQueue.global().async { [self] in
            if !colorDic.contains(where: { $0.key == model.appName }) {
                let iconImage = NSWorkspace.shared.icon(forFile: model.appPath)
                let colors = iconImage.getColors()
                if let colorStr = colors?.primary.hexString(true),
                   !colorStr.isEmpty {
                    colorDic[model.appName] = colorStr
                    userDefault.set(colorDic, forKey: PrefKey.appColorData.rawValue)
                }
            }
        }
    }
    
    func colorWith(_ model: PasteboardModel) -> NSColor {
        if let colorStr = colorDic[model.appName], let color = NSColor(colorStr) {
            return color
        }
        let iconImage = NSWorkspace.shared.icon(forFile: model.appPath)
        let colors = iconImage.getColors()
        updateColor(model)
        return colors?.primary ?? NSColor.clear
    }
}



