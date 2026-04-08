//
//  HexColorValidator.swift
//  PasteDirect
//
//  Created by Claude on 2026/01/05.
//

import AppKit

extension NSColor {
    /// 通过 hex 字符串创建颜色，支持 #RGB, #RRGGBB, 0xRRGGBB 等格式
    convenience init?(_ hex: String) {
        guard let normalized = HexColorValidator.parseColor(from: hex),
              normalized.count == 7 else { return nil }
        let hexStr = String(normalized.dropFirst()) // 去掉 #
        guard let value = UInt64(hexStr, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

struct HexColorValidator {

    // 支持的格式：#RGB, #RRGGBB, RGB, RRGGBB, 0xRRGGBB, #RRGGBBAA, #AARRGGBB, 0xAARRGGBB
    private static let hexPattern = "^(?:#|0x)?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"

    /// 严格模式：检查字符串是否完全是 hex 颜色
    static func isValidHexColor(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 正则匹配
        guard let regex = try? NSRegularExpression(pattern: hexPattern),
              regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil else {
            return nil
        }

        // 验证是否能成功解析为 NSColor
        return parseColor(from: trimmed)
    }

    /// 解析 hex 字符串为 NSColor
    static func parseColor(from text: String?) -> String? {
        guard let text = text else { return nil }
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除 0x 前缀
        if normalized.lowercased().hasPrefix("0x") {
            normalized = String(normalized.dropFirst(2))
        }

        // 确保有 # 前缀
        if !normalized.hasPrefix("#") {
            normalized = "#" + normalized
        }


        // 处理 8 位格式（ARGB/RGBA，智能检测）
        if normalized.count == 9 { // #RRGGBBAA 或 #AARRGGBB
            let firstTwo = String(normalized.prefix(3).suffix(2)) // 前2位
            let lastTwo = String(normalized.suffix(2))            // 后2位

            let firstIsFF = firstTwo.uppercased() == "FF"
            let lastIsFF = lastTwo.uppercased() == "FF"

            if firstIsFF && lastIsFF {
                // 都是 FF，优先按 RGBA 处理（提取前6位）
                normalized = String(normalized.prefix(7)) // #RRGGBB
            } else if firstIsFF {
                // 前2位是 FF → ARGB 格式 #AARRGGBB
                // 提取中间6位 RRGGBB
                let startIndex = normalized.index(normalized.startIndex, offsetBy: 3)
                let endIndex = normalized.index(normalized.startIndex, offsetBy: 9)
                normalized = "#" + String(normalized[startIndex..<endIndex])
            } else if lastIsFF {
                // 后2位是 FF → RGBA 格式 #RRGGBBAA
                // 提取前6位 RRGGBB
                normalized = String(normalized.prefix(7)) // #RRGGBB
            } else {
                // 都不是 FF，拒绝识别
                return nil
            }
        }

        // 扩展 #RGB 为 #RRGGBB
        if normalized.count == 4 { // #RGB
            let r = normalized[normalized.index(normalized.startIndex, offsetBy: 1)]
            let g = normalized[normalized.index(normalized.startIndex, offsetBy: 2)]
            let b = normalized[normalized.index(normalized.startIndex, offsetBy: 3)]
            normalized = "#\(r)\(r)\(g)\(g)\(b)\(b)"
        }

        return normalized
    }

    /// 计算文本颜色（基于背景色亮度）
    static func textColor(for backgroundColor: NSColor) -> NSColor {
        guard let rgb = backgroundColor.usingColorSpace(.deviceRGB) else {
            return .textColor
        }

        // 计算相对亮度 (WCAG 标准)
        let luminance = 0.2126 * rgb.redComponent
                      + 0.7152 * rgb.greenComponent
                      + 0.0722 * rgb.blueComponent

        // 亮度阈值：0.5
        return luminance > 0.5 ? .black : .white
    }
}
