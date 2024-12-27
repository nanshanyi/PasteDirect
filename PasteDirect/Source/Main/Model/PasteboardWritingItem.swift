//
//  File.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/8/2.
//

import AppKit

final class PasteboardWritingItem: NSObject {
    private let data: Data
    private let type: PasteboardType

    init(data: Data, type: PasteboardType) {
        self.data = data
        self.type = type
    }
}

extension PasteboardWritingItem: NSPasteboardWriting {
    func writableTypes(for pasteboard: NSPasteboard) -> [PasteboardType] {
        [type]
    }

    func pasteboardPropertyList(forType type: PasteboardType) -> Any? {
        data
    }
}
