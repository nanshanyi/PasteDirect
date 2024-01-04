//
//  PasteBoard.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

class PasteBoard {
    static let main = PasteBoard()

    private let pasteboard = NSPasteboard.general
    private let timerInterval = 1.0
    private var changeCount: Int
    private var pasteModel: PasteboardModel?

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

        if let model = pasteModel {
            changeCount = pasteboard.changeCount
            mainDataStore.addOldModel(model)
            pasteModel = nil
            return
        }

        guard let item = pasteboard.pasteboardItems?.first else { return }
        mainDataStore.addNewItem(item)
        changeCount = pasteboard.changeCount
    }

    func pasteData(_ data: PasteboardModel, _ isAttribute: Bool = true) {
        pasteModel = data
        NSPasteboard.general.clearContents()
        if data.type == .string && !isAttribute {
            NSPasteboard.general.setString(data.attributeString?.string ?? "", forType: .string)
        } else {
            NSPasteboard.general.setData(data.data, forType: data.pType)
        }
    }
}
