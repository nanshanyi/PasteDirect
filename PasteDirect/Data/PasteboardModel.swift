//
//  PasteboardModel.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Foundation
import AppKit

struct PasteboardModel {
    
    public enum ModelType {
        case none
        case image
        case string
    }
    public enum PasteboardType: Int {
        case none
        case rtf
        case rtfd
        case string
        case html
        case png
    }
    
    
    public let pasteBoardType: PasteboardType
    public let data: Data
    public let hashValue: Int
    public let date:Date
    public let appPath: String
    public let appName: String
    public var dataString: String = ""
    
    public var pType: NSPasteboard.PasteboardType {
        switch pasteBoardType {
        case .rtf: return .rtf
        case .rtfd: return .rtfd
        case .string: return .string
        case .html: return .html
        case .png: return .png
        default: return .string
        }
    }
    
    public var attributeString: NSAttributedString? {
        switch pasteBoardType {
        case .rtf:
           return NSAttributedString(rtf:data , documentAttributes: nil)
        case .rtfd:
            return NSAttributedString(rtfd: data, documentAttributes: nil)
        case .string:
            return try? NSAttributedString(data: data, options: [:], documentAttributes: nil)
        default:
            return nil
        }
    }
    
    public var type: ModelType {
        let pTypes:[PasteboardType] = [.rtf, .rtfd, .string]
        if pTypes.contains(pasteBoardType) {
            return .string
        } else if pasteBoardType == .png {
            return .image
        }
        return .none
    }
    
    static func model(with item: NSPasteboardItem) -> PasteboardModel? {
        let app = WindowInfo.appOwningFrontmostWindow()
        var tData: Data?
        var pType: PasteboardType = .none
        
        for type in item.types {
            if let data = item.data(forType: type) {
                tData = data
                switch type {
                case .rtf:
                    pType = .rtf
                case .rtfd:
                    pType = .rtfd
                case .string:
                    pType = .string
                case .png:
                    pType = .png
                default:
                    pType = .none
                }
            }
            if pType != .none {
                var model = PasteboardModel(pasteBoardType: pType, data: tData!, hashValue: tData!.hashValue, date: Date(), appPath: app?.url.path ?? "", appName: app?.name ?? "")
                model.dataString = model.attributeString?.string ?? ""
                return model
            }
        }
        return nil
    }
    
}

extension PasteboardModel: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
}
