//
//  DemoData.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/11/23.
//

import AppKit

/// 数据目录名(位于 Application Support 下)。
/// DEBUG 构建用 `-DemoData YES` 启动时切到独立的演示库 `paste-demo`,不读写真实剪贴板历史。
enum StorageLocation {
    static let folderName: String = {
        #if DEBUG
        if DemoData.isEnabled { return "paste-demo" }
        #endif
        return "paste"
    }()
}

#if DEBUG
/// 演示数据:演示库为空时写入一批虚构条目,用于截 README 图等场景,避免露出真实剪贴板内容。
/// 用法: open PasteDirect.app --args -DemoData YES
enum DemoData {
    static let isEnabled = UserDefaults.standard.bool(forKey: "DemoData")

    struct Entry {
        let model: PasteboardModel
        /// 图片原图(存入 ImageBlobStore);非图片为 nil
        let original: Data?
    }

    private struct App {
        let path: String
        var name: String {
            let name = FileManager.default.displayName(atPath: path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }

        static let safari = App(path: "/Applications/Safari.app")
        static let chrome = App(path: "/Applications/Google Chrome.app")
        static let xcode = App(path: "/Applications/Xcode.app")
        static let vscode = App(path: "/Applications/Visual Studio Code.app")
        static let wechat = App(path: "/Applications/WeChat.app")
        static let notes = App(path: "/System/Applications/Notes.app")
        static let terminal = App(path: "/System/Applications/Utilities/Terminal.app")
        static let preview = App(path: "/System/Applications/Preview.app")
        static let calendar = App(path: "/System/Applications/Calendar.app")
        static let sfSymbols = App(path: "/Applications/SF Symbols.app")
    }

    static func makeEntries(now: Date = Date()) -> [Entry] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var entries: [Entry?] = [
            text("产品评审会\n周四 14:00 – 15:30\n3F 会议室 Orion", app: .calendar, date: ago(60 * 26), pinnedAt: ago(30)),
            text("""
            func greet(_ name: String) -> String {
                let hour = Calendar.current.component(.hour, from: .now)
                let period = hour < 12 ? "早上好" : "下午好"
                return "\\(period)，\\(name)！"
            }
            """, app: .xcode, date: ago(60 * 50), pinnedAt: ago(20)),
            text("https://github.com/nanshanyi/PasteDirect", app: .safari, date: ago(1)),
            text("#5E5CE6", app: .sfSymbols, date: ago(3)),
            image(drawLandscape(), app: .preview, date: ago(6)),
            text("收到，明天见 👋", app: .wechat, date: ago(9)),
            text("""
            周末出行清单
            · 充电宝和数据线
            · 相机电池 ×2
            · 雨伞
            · 提前预约博物馆门票
            · 记得给植物浇水 🌱
            """, app: .notes, date: ago(14)),
            text("git log --oneline --graph --decorate -20", app: .terminal, date: ago(21)),
            text("#34C759", app: .xcode, date: ago(28)),
            image(drawChart(), app: .chrome, date: ago(35)),
            text("""
            {
              "name": "PasteDirect",
              "platform": "macOS",
              "features": ["search", "filter", "preview", "pin"]
            }
            """, app: .vscode, date: ago(47)),
            text("https://developer.apple.com/documentation/appkit", app: .chrome, date: ago(58)),
            text("Simplicity is the ultimate sophistication.", app: .safari, date: ago(75)),
            text("#FF9F0A", app: .vscode, date: ago(92)),
            image(drawPalette(), app: .preview, date: ago(110)),
            text("把常用的内容置顶，随时一键粘贴。", app: .notes, date: ago(130)),
            text("brew install --cask iina", app: .terminal, date: ago(160)),
            text("#FF375F", app: .sfSymbols, date: ago(190)),
        ]
        entries.reverse()
        return entries.compactMap { $0 }
    }

    // MARK: - 条目构造

    private static func text(_ string: String, app: App, date: Date, pinnedAt: Date? = nil) -> Entry {
        let data = Data(string.utf8)
        let model = PasteboardModel(
            pasteboardType: .string,
            data: data,
            showData: nil,
            hashValue: data.contentHash,
            date: date,
            appPath: app.path,
            appName: app.name,
            dataString: string,
            length: string.count,
            pinnedDate: pinnedAt
        )
        return Entry(model: model, original: nil)
    }

    private static func image(_ png: Data?, app: App, date: Date) -> Entry? {
        guard let png, let thumb = ImageThumbnail.make(from: png) else { return nil }
        let model = PasteboardModel(
            pasteboardType: .png,
            data: thumb.thumbnail,
            showData: nil,
            hashValue: png.contentHash,
            date: date,
            appPath: app.path,
            appName: app.name,
            dataString: "",
            length: 0,
            imageWidth: Int(thumb.pixelSize.width),
            imageHeight: Int(thumb.pixelSize.height)
        )
        return Entry(model: model, original: png)
    }

    // MARK: - 图片绘制

    private static func render(width: Int, height: Int, _ draw: (CGRect) -> Void) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// 日落山景
    private static func drawLandscape() -> Data? {
        render(width: 1600, height: 1000) { rect in
            NSGradient(colors: [color(0xFFB36B), color(0xFF6F91), color(0x6A4C93)])?
                .draw(in: rect, angle: 90)
            color(0xFFE29A).withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: CGRect(x: 1020, y: 430, width: 260, height: 260)).fill()

            let layers: [(UInt32, [CGFloat])] = [
                (0x8E5A9E, [380, 560, 470, 640, 520, 600, 430]),
                (0x5B3F7A, [260, 420, 330, 480, 360, 300, 400]),
                (0x2E2350, [140, 230, 170, 260, 190, 240, 150]),
            ]
            for (hex, peaks) in layers {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: 0, y: 0))
                let step = rect.width / CGFloat(peaks.count - 1)
                for (i, y) in peaks.enumerated() {
                    path.line(to: CGPoint(x: CGFloat(i) * step, y: y))
                }
                path.line(to: CGPoint(x: rect.width, y: 0))
                path.close()
                color(hex).setFill()
                path.fill()
            }
        }
    }

    /// 柱状图
    private static func drawChart() -> Data? {
        render(width: 1200, height: 800) { rect in
            color(0xF7F7FA).setFill()
            rect.fill()
            let title: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: color(0x1D1D1F),
            ]
            ("每月活跃用户" as NSString).draw(at: CGPoint(x: 80, y: 680), withAttributes: title)

            let values: [CGFloat] = [0.35, 0.48, 0.42, 0.6, 0.72, 0.66, 0.85, 0.93]
            let barWidth: CGFloat = 90
            let gap: CGFloat = 40
            let chartHeight: CGFloat = 520
            for (i, value) in values.enumerated() {
                let bar = CGRect(x: 90 + CGFloat(i) * (barWidth + gap), y: 90,
                                 width: barWidth, height: chartHeight * value)
                NSGradient(starting: color(0x5E5CE6), ending: color(0x64D2FF))?
                    .draw(in: NSBezierPath(roundedRect: bar, xRadius: 14, yRadius: 14), angle: 90)
            }
            color(0xD2D2D7).setFill()
            CGRect(x: 80, y: 84, width: 1040, height: 3).fill()
        }
    }

    /// 配色色板
    private static func drawPalette() -> Data? {
        render(width: 1200, height: 900) { rect in
            color(0x1C1C1E).setFill()
            rect.fill()
            let hexes: [UInt32] = [0xFF375F, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x64D2FF, 0x0A84FF, 0x5E5CE6, 0xBF5AF2, 0xAC8E68]
            let size: CGFloat = 300
            let gap: CGFloat = 60
            for (i, hex) in hexes.enumerated() {
                let col = CGFloat(i % 3)
                let row = CGFloat(i / 3)
                let swatch = CGRect(x: 60 + col * (size + gap), y: 60 + row * (size - 30 + gap / 2),
                                    width: size, height: size - 60)
                color(hex).setFill()
                NSBezierPath(roundedRect: swatch, xRadius: 36, yRadius: 36).fill()
            }
        }
    }
}
#endif
