//
//  PasteboardType.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/11.
//

import AppKit

enum PasteboardType: Int, CaseIterable {
    case none = 0
    case rtf = 1
    case rtfd = 2
    case string = 3
    case png = 5
    
    var pType: NSPasteboard.PasteboardType {
        switch self {
        case .rtf: return .rtf
        case .rtfd: return .rtfd
        case .string: return .string
        case .png: return .png
        default: return .string
        }
    }
    
    init(for type: NSPasteboard.PasteboardType) {
        switch type {
        case .rtf: self = .rtf
        case .rtfd: self = .rtfd
        case .string: self = .string
        case .png: self = .png
        default: self = .none
        }
    }
}
