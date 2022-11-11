//
//  PasteBoard.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Foundation
import AppKit


class PasteBoard {
    static let main = PasteBoard()
    
    private let pasteboard = NSPasteboard.general
    private let timerInterval = 1.0
    private var changeCount: Int
    
    init() {
        changeCount = pasteboard.changeCount
    }
    
    
    func startListening() {
        Timer.scheduledTimer(timeInterval: timerInterval,
                             target: self,
                             selector: #selector(checkForChangesInPasteboard),
                             userInfo: nil,
                             repeats: true)
    }
    
    
    @objc func checkForChangesInPasteboard() {
        guard pasteboard.changeCount != changeCount else {
            return
        }
        
        guard let item = pasteboard.pasteboardItems?.first else { return }
        mainDataStore.addNewItem(item: item)
        changeCount = pasteboard.changeCount
    }
    
    func setData(_ data: PasteboardModel, _ isAttribute:Bool = true) {
        var data = data
        NSPasteboard.general.clearContents()
        if data.type == .string && !isAttribute{
            NSPasteboard.general.setString(data.attributeString?.string ?? "", forType: .string)
        } else {
            NSPasteboard.general.setData(data.data, forType: data.pType)
        }        
    }
}
