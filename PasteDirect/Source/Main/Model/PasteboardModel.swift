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
    /// 图片经 OCR 识别出的文本;仅图片类型可能非 nil,用于让图片内容可被搜索。非图片项为 nil
    let ocrText: String?

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
         length: Int,
         ocrText: String? = nil)
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
        self.ocrText = ocrText

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
            length: length,
            ocrText: ocrText
        )
    }

    /// 返回写入了 OCR 文本的新实例(图片专属)
    func withOCRText(_ text: String) -> PasteboardModel {
        PasteboardModel(
            pasteboardType: pasteboardType,
            data: data,
            showData: showData,
            hashValue: hashValue,
            date: date,
            appPath: appPath,
            appName: appName,
            dataString: dataString,
            length: length,
            ocrText: text
        )
    }

    /// 用一段纯文本构造一条 `.string` model(用于把图片 OCR 出的文字当作文本复制/粘贴)。
    /// 继承来源图片的 app 信息,日期取当前时间。
    @MainActor
    static func makeText(_ text: String, from source: PasteboardModel) -> PasteboardModel {
        let data = Data(text.utf8)
        return PasteboardModel(
            pasteboardType: .string,
            data: data,
            showData: nil,
            hashValue: data.hashValue,
            date: Date(),
            appPath: source.appPath,
            appName: source.appName,
            dataString: text,
            length: text.count
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
