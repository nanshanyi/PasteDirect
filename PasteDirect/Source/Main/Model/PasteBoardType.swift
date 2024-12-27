//
//  PasteboardType.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/11.
//

import AppKit

typealias PasteboardType = NSPasteboard.PasteboardType

extension PasteboardType {
    static var supportTypes: [PasteboardType] = [.rtf, .rtfd, .string, .png, .tiff]
    func isImage() -> Bool {
        self == .png || self == .tiff
    }
    
    func isText() -> Bool { !isImage() }
}
