//
//  PasteboardModel.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import AppKit
import Foundation

/// rawValue 会写入数据库 kindCode 列(仅派生类型),编号发布后不可修改或复用,新增类型只能追加新编号。
enum PasteModelType: Int, Sendable {
    case none = 0
    case image = 1
    case string = 2
    case color = 3
    case link = 4

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

    /// 由内容推出、存库时打标签(kindCode 列,值为 rawValue)的类型,按此顺序依次匹配。
    /// 新增派生类型:加 case、在此登记、在 PasteboardModel.derivedType 里补规则,
    /// 并递增 PasteSQLManager.kindRulesVersion 触发旧数据回填。
    static let derivedTypes: [PasteModelType] = [.color, .link]

    /// 顶栏分段与筛选弹窗展示的类型(顺序即界面顺序)
    static let filterable: [PasteModelType] = [.string, .link, .image, .color]

    var isDerived: Bool { Self.derivedTypes.contains(self) }

    var symbolName: String {
        switch self {
        case .image: return "photo"
        case .string: return "doc.text"
        case .color: return "paintpalette"
        case .link: return "link"
        case .none: return "questionmark"
        }
    }

    var string: String {
        switch self {
        case .image: return String(localized: "Image")
        case .string: return String(localized: "Text")
        case .color: return String(localized: "Color")
        case .link: return String(localized: "Link")
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
    /// 由内容推出的派生类型(颜色/链接等),同时也是写入数据库 kind 列的值
    let derivedType: PasteModelType?
    /// 图片经 OCR 识别出的文本;仅图片类型可能非 nil,用于让图片内容可被搜索。非图片项为 nil
    let ocrText: String?
    /// 图片原图的像素尺寸。图片外置到文件后，不加载原图也能算预览尺寸和显示尺寸文案;非图片项为 nil
    let imageWidth: Int?
    let imageHeight: Int?
    /// 置顶时间。nil 表示未置顶;非 nil 时该条恒排在未置顶项之前,多个置顶项按此时间倒序。
    let pinnedDate: Date?

    /// 是否已置顶
    var isPinned: Bool { pinnedDate != nil }

    var type: PasteModelType {
        derivedType ?? PasteModelType(with: pasteboardType)
    }

    /// 由文本内容推出派生类型;init 与数据库回填共用,保证两处规则一致
    static func derivedType(forText text: String, type: PasteboardType) -> PasteModelType? {
        PasteModelType.derivedTypes.first { candidate in
            switch candidate {
            case .color:
                return HexColorValidator.isValidHexColor(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
            case .link:
                // 富文本保留原样展示，不算链接
                return type == .string && linkURL(in: text) != nil
            default:
                return false
            }
        }
    }

    /// 单段、无空白的 http(s) 链接
    static func linkURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2048, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
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
         ocrText: String? = nil,
         imageWidth: Int? = nil,
         imageHeight: Int? = nil,
         pinnedDate: Date? = nil)
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
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.pinnedDate = pinnedDate

        if pasteboardType.isText() {
            let trimmed = dataString.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hexColorString = HexColorValidator.isValidHexColor(trimmed)
        } else {
            self.hexColorString = nil
        }
        self.derivedType = pasteboardType.isText() ? Self.derivedType(forText: dataString, type: pasteboardType) : nil
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
            ocrText: ocrText,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            pinnedDate: pinnedDate
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
            ocrText: text,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            pinnedDate: pinnedDate
        )
    }

    /// 返回更新了置顶状态的新实例。置顶传 `Date()`,取消置顶传 `nil`。
    func withPinnedDate(_ date: Date?) -> PasteboardModel {
        PasteboardModel(
            pasteboardType: pasteboardType,
            data: data,
            showData: showData,
            hashValue: hashValue,
            date: self.date,
            appPath: appPath,
            appName: appName,
            dataString: dataString,
            length: length,
            ocrText: ocrText,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            pinnedDate: date
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
            hashValue: data.contentHash,
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
            // 优先用记录的原图像素尺寸(列表展示的是缩略图，其 size 不再代表原图)
            if let w = imageWidth, let h = imageHeight, w > 0, h > 0 {
                return "\(w) × \(h) \(String(localized: "pixels"))"
            }
            guard let image else { return "" }
            return "\(Int(image.size.width)) × \(Int(image.size.height)) \(String(localized: "pixels"))"
        case .string, .link:
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
        var imgW: Int?
        var imgH: Int?

        if type.isText() {
            att = NSAttributedString(with: data, type: type) ?? NSAttributedString()
            guard !att.string.allSatisfy({ $0.isWhitespace }) else { return nil }
            let showAtt = att.length > maxLength ? att.attributedSubstring(from: NSMakeRange(0, maxLength)) : att
            showData = showAtt.toData(with: type)
        } else if let size = ImageThumbnail.pixelSize(of: data) {
            // 图片：记录原图像素尺寸。此处 data 仍是原图(用于算 hash、并稍后由 DataStore 外置)，
            // 缩略图替换在 DataStore.addNewItem 中完成。
            imgW = Int(size.width)
            imgH = Int(size.height)
        }
        self.init(pasteboardType: type,
                  data: data,
                  showData: showData,
                  hashValue: data.contentHash,
                  date: Date(),
                  appPath: app.path,
                  appName: app.name,
                  dataString: att.string,
                  length: att.length,
                  imageWidth: imgW,
                  imageHeight: imgH)
    }

    /// 替换 data 字段(其余不变)的新实例。
    /// 入库时用来把原图换成缩略图;OCR 时用来临时换回原图。
    /// `hashValue` 不变(仍是原图内容哈希)，故去重/主键/OCR cache key 不受影响。
    func replacingData(_ newData: Data) -> PasteboardModel {
        replacingData(newData, type: pasteboardType)
    }

    /// 同时替换 data 与 pasteboardType 的新实例。
    /// 图片原图重编码(如 TIFF→PNG)后用，保证存盘字节、列表展示、粘贴回写的类型一致。
    /// `hashValue` 仍沿用原图内容哈希，不随重编码改变(去重/主键/外置文件名不受影响)。
    func replacingData(_ newData: Data, type: PasteboardType) -> PasteboardModel {
        PasteboardModel(
            pasteboardType: type,
            data: newData,
            showData: showData,
            hashValue: hashValue,
            date: date,
            appPath: appPath,
            appName: appName,
            dataString: dataString,
            length: length,
            ocrText: ocrText,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            pinnedDate: pinnedDate
        )
    }
}
