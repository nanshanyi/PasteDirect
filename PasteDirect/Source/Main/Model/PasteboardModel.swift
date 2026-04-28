//
//  PasteboardModel.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

enum PasteModelType: Sendable {
    case none
    case image
    case string
    case color

    init(with type: PasteboardType) {
        switch type {
        case .rtf, .rtfd, .string:
            self = .string
        case .png, .tiff:
            self = .image
        default:
            self = .none
        }
    }

    var string: String {
        switch self {
        case .image: return String(localized: "Image")
        case .string: return String(localized: "Text")
        case .color: return String(localized: "Color")
        default: return String(localized: "Unknown")
        }
    }
}

struct PasteboardModel: Sendable, Equatable, Hashable {
    let pasteboardType: PasteboardType
    let data: Data
    let showData: Data?
    let hashValue: Int
    let date: Date
    let appPath: String
    let appName: String
    let dataString: String
    let length: Int
    let hexColorString: String?

    var type: PasteModelType {
        if hexColorString != nil {
            return .color
        }
        return PasteModelType(with: pasteboardType)
    }

    @MainActor
    var writeItem: PasteboardWritingItem {
        PasteboardWritingItem(data: data, type: pasteboardType)
    }

    /// 按需从 showData/data 构造 NSAttributedString（仅在 UI 层使用）
    @MainActor
    var attributeString: NSAttributedString? {
        NSAttributedString(with: showData ?? data, type: pasteboardType)
    }

    init(pasteboardType: PasteboardType,
         data: Data,
         showData: Data?,
         hashValue: Int,
         date: Date,
         appPath: String,
         appName: String,
         dataString: String,
         length: Int)
    {
        self.pasteboardType = pasteboardType
        self.data = data
        self.showData = showData
        self.hashValue = hashValue
        self.date = date
        self.appPath = appPath
        self.appName = appName
        self.dataString = dataString
        self.length = length

        if pasteboardType.isText() {
            let trimmed = dataString.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hexColorString = HexColorValidator.isValidHexColor(trimmed)
        } else {
            self.hexColorString = nil
        }
    }

    /// 返回更新了日期的新实例
    func withUpdatedDate() -> PasteboardModel {
        PasteboardModel(
            pasteboardType: pasteboardType,
            data: data,
            showData: showData,
            hashValue: hashValue,
            date: Date(),
            appPath: appPath,
            appName: appName,
            dataString: dataString,
            length: length
        )
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    func sizeString(or image: NSImage? = nil) -> String {
        switch type {
        case .none:
            return ""
        case .image:
            guard let image else { return "" }
            return "\(Int(image.size.width)) × \(Int(image.size.height)) \(String(localized: "pixels"))"
        case .string:
            return "\(Self.formatter.string(from: NSNumber(value: length)) ?? "")\(String(localized: "characters"))"
        case .color:
            return "\(String(localized: "Color"))\(String(localized: "colon"))\(hexColorString ?? String(localized: "Unknown"))"
        }
    }

    static func == (lhs: PasteboardModel, rhs: PasteboardModel) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hashValue)
    }
}

// MARK: - 从剪贴板创建

extension PasteboardModel {
    @MainActor
    init?(with item: NSPasteboardItem) {
        guard let app = IgnoredAppsManager.shared.frontmostApplication() else { return nil }
        guard let type = item.availableType(from: PasteboardType.supportTypes) else { return nil }
        guard let data = item.data(forType: type) else { return nil }
        var showData: Data?
        var att = NSAttributedString()

        if type.isText() {
            att = NSAttributedString(with: data, type: type) ?? NSAttributedString()
            guard !att.string.allSatisfy({ $0.isWhitespace }) else { return nil }
            let showAtt = att.length > maxLength ? att.attributedSubstring(from: NSMakeRange(0, maxLength)) : att
            showData = showAtt.toData(with: type)
        }
        self.init(pasteboardType: type,
                  data: data,
                  showData: showData,
                  hashValue: data.hashValue,
                  date: Date(),
                  appPath: app.path,
                  appName: app.name,
                  dataString: att.string,
                  length: att.length)
    }
}
