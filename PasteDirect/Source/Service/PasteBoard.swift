//
//  PasteBoard.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

@MainActor
final class PasteBoard {
    static let main = PasteBoard()

    private let pasteboard = NSPasteboard.general
    private let timerInterval = 0.5
    private var changeCount: Int
    private var pasteModel: PasteboardModel?

    init() {
        changeCount = pasteboard.changeCount
    }

    func startListening() {
        Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) {[weak self] _ in
            self?.checkForChangesInPasteboard()
        }
    }

    private func checkForChangesInPasteboard() {
        guard pasteboard.changeCount != changeCount else {
            return
        }

        if pasteModel != nil {
            changeCount = pasteboard.changeCount
            pasteModel = nil
            return
        }

        guard let item = pasteboard.pasteboardItems?.first else { return }
        PasteDataStore.main.addNewItem(item)
        changeCount = pasteboard.changeCount
    }

    func pasteData(_ data: PasteboardModel?, _ isOriginal: Bool = false) {
        guard let data else { return }
        let updated = data.withUpdatedDate()
        pasteModel = updated
        PasteDataStore.main.insertModel(updated)
        NSPasteboard.general.clearContents()
        if updated.type == .string, !isOriginal {
            NSPasteboard.general.setString(updated.dataString, forType: .string)
        } else if updated.type == .color {
            let string = isOriginal ? updated.dataString : updated.hexColorString
            NSPasteboard.general.setString(string ?? updated.dataString, forType: .string)
        } else {
            NSPasteboard.general.setData(updated.data, forType: updated.pasteboardType)
        }
    }
}
