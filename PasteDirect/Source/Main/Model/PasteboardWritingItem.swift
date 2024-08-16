//
//  File.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/8/2.
//

import AppKit

final class PasteboardWritingItem: NSObject {
    private let data: Data
    private let type: NSPasteboard.PasteboardType

    init(data: Data, type: NSPasteboard.PasteboardType) {
        self.data = data
        self.type = type
    }
}

extension PasteboardWritingItem: NSPasteboardWriting {
    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [type]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        data
    }
}
