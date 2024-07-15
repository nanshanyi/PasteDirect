//
//  PasteboardModel.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

enum PasteModelType {
    case none
    case image
    case string
    
    init(with type: PasteboardType) {
        switch type {
        case .rtf, .rtfd, .string, .html:
            self = .string
        case .png:
            self = .image
        default:
            self = .none
        }
    }
    
    var string: String {
        switch self {
        case .image: return "图片"
        case .string: return "文本"
        default: return "未知"
        }
    }
}

struct PasteboardModel {
    let pasteBoardType: PasteboardType
    let data: Data
    let hashValue: Int
    let date: Date
    let appPath: String
    let appName: String
    let attributeString: NSAttributedString?
    let pType: NSPasteboard.PasteboardType
    let dataString: String
    let type: PasteModelType
    
    init(pasteBoardType: PasteboardType,
         data: Data,
         hashValue: Int,
         date: Date,
         appPath: String,
         appName: String) {
        self.pasteBoardType = pasteBoardType
        self.data = data
        self.hashValue = hashValue
        self.date = date
        self.appPath = appPath
        self.appName = appName
        self.attributeString = NSAttributedString(with: data, type: pasteBoardType)
        self.pType = pasteBoardType.pType
        self.dataString = attributeString?.string ?? ""
        self.type = PasteModelType(with: pasteBoardType)
    }
    
    init?(with item: NSPasteboardItem) {
        let app = WindowInfo.appOwningFrontmostWindow()
        for type in item.types {
            guard let data = item.data(forType: type) else { continue }
            let pType = PasteboardType(for: type)
            guard pType != .none else { continue }
            self.init(pasteBoardType: pType,
                      data: data,
                      hashValue: data.hashValue,
                      date: Date(),
                      appPath: app?.url.path ?? "",
                      appName: app?.name ?? "")
            return
        }
        return nil
    }
    
    private let formatter = NumberFormatter().then {
        $0.numberStyle = .decimal
    }
    
    func sizeString(or image: NSImage? = nil) -> String {
        switch type {
        case .none:
            return ""
        case .image:
            guard let image else { return "" }
            return "\(Int(image.size.width)) ×\(Int(image.size.height)) 像素"
        case .string:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return "\(formatter.string(from: NSNumber(value: dataString.count)) ?? "")个字符"
        }
    }
    
}

extension PasteboardModel: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
