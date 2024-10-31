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
        case .rtf, .rtfd, .string:
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

final class PasteboardModel {
    let pasteBoardType: PasteboardType
    let data: Data
    let showData: Data?
    let hashValue: Int
    private(set) var date: Date
    let appPath: String
    let appName: String
    let dataString: String
    let length: Int
    let attributeString: NSAttributedString?
    private(set) lazy var pType = pasteBoardType.pType
    private(set) lazy var type: PasteModelType = .init(with: pasteBoardType)
    private(set) lazy var writeItem = PasteboardWritingItem(data: data, type: pType)
    
    init(pasteBoardType: PasteboardType,
         data: Data,
         showData: Data?,
         hashValue: Int,
         date: Date,
         appPath: String,
         appName: String,
         dataString: String,
         length: Int,
         attributeString: NSAttributedString? = nil)
    {
        self.pasteBoardType = pasteBoardType
        self.data = data
        self.showData = showData
        self.hashValue = hashValue
        self.date = date
        self.appPath = appPath
        self.appName = appName
        self.dataString = dataString
        self.length = length
        self.attributeString = attributeString
    }
    
    convenience init?(with item: NSPasteboardItem) {
        let app = WindowInfo.appOwningFrontmostWindow()
        for type in item.types {
            guard let data = item.data(forType: type) else { continue }
            let pType = PasteboardType(for: type)
            guard pType != .none else { continue }
            var showData: Data?
            var showAtt: NSAttributedString?
            let att = NSAttributedString(with: data, type: pType) ?? NSAttributedString()
            if pType != .png {
                guard !att.string.allSatisfy({ $0.isWhitespace }) else { continue }
                showAtt = att.length > maxLength ? att.attributedSubstring(from: NSMakeRange(0, maxLength)) : att
                showData = showAtt?.toData(with: pType)
            }

            self.init(pasteBoardType: pType,
                      data: data,
                      showData: showData,
                      hashValue: data.hashValue,
                      date: Date(),
                      appPath: app?.url.path ?? "",
                      appName: app?.name ?? "",
                      dataString: att.string,
                      length: att.length,
                      attributeString: showAtt)
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
            return "\(Int(image.size.width)) × \(Int(image.size.height)) 像素"
        case .string:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return "\(formatter.string(from: NSNumber(value: length)) ?? "")个字符"
        }
    }
    
    func updateDate() {
        date = Date()
    }
}

extension PasteboardModel: Equatable {
    static func == (lhs: PasteboardModel, rhs: PasteboardModel) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
