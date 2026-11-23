//
//  AppColor.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/11/23.
//

import AppKit

/// 主面板的自定义颜色,集中定义。
///
/// 规则:
/// - 能直接用系统语义色(labelColor、controlAccentColor 等)的地方不在这里定义。
/// - 面板是 macOS 26 玻璃背景,系统标签色会被 vibrancy 改变实际亮度,
///   需要精确控制明暗层级的文字用这里的显式颜色。
/// - 所有颜色都是动态色,在 updateLayer / draw 中解析,深浅模式切换时自动更新。
enum AppColor {
    // MARK: - 基础

    /// 按外观返回深色/浅色两套值的动态色
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { isDark($0) ? dark : light }
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// 深色模式文字基色 rgb(235,235,245),与系统 labelColor 同色相
    private static let darkText = NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 1)
    /// 浅色模式文字基色 rgb(29,29,31)
    private static let lightText = NSColor(srgbRed: 29 / 255, green: 29 / 255, blue: 31 / 255, alpha: 1)
    /// systemGray 基色 rgb(120,120,128),用于半透明填充
    private static let systemGrayBase = NSColor(srgbRed: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 1)

    // MARK: - 顶栏

    /// 顶栏控件(分段底槽、搜索框、图标按钮悬停)共用的底色。
    /// 用黑/白叠加而不是 systemGray:浅色模式的玻璃面板本身就是中灰,灰色叠上去看不出边界。
    static let toolbarFill = dynamic(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.10))

    /// 顶栏次要图标色(设置按钮等),与分段按钮未选中标题一致
    static let toolbarIcon = dynamic(light: lightText.withAlphaComponent(0.62), dark: darkText.withAlphaComponent(0.6))

    /// 分段按钮选中项的胶囊
    static let segmentPill = dynamic(light: .white, dark: .white.withAlphaComponent(0.18))
    static let segmentPillShadow = NSColor.black.withAlphaComponent(0.15)

    /// 分段按钮文字。标题与个数用同一基色、不同透明度,保证个数始终比标题淡一档
    static func segmentText(selected: Bool, isCount: Bool) -> NSColor {
        switch (selected, isCount) {
        case (true, false): return dynamic(light: lightText, dark: darkText)
        case (true, true): return dynamic(light: lightText.withAlphaComponent(0.55), dark: darkText.withAlphaComponent(0.55))
        case (false, false): return toolbarIcon
        case (false, true): return dynamic(light: lightText.withAlphaComponent(0.36), dark: darkText.withAlphaComponent(0.32))
        }
    }

    /// 搜索框占位符与放大镜图标
    static let searchPlaceholder = dynamic(
        light: NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.6),
        dark: darkText.withAlphaComponent(0.35)
    )

    /// 搜索框聚焦描边
    static let searchFocusRing = NSColor.controlAccentColor.withAlphaComponent(0.8)
    /// 搜索框聚焦时的底色:比未聚焦更亮,配合描边让输入状态一眼可见
    static let searchFocusedFill = dynamic(light: .white.withAlphaComponent(0.85), dark: .white.withAlphaComponent(0.16))

    /// 顶部拖拽把手;悬停或拖动中更亮
    static func grabber(active: Bool) -> NSColor {
        NSColor.labelColor.withAlphaComponent(active ? 0.5 : 0.25)
    }

    // MARK: - 预览

    /// 预览弹窗底部类型名后面的信息行(字数、尺寸、来源等)。
    /// popover 也是半透明材质,secondaryLabelColor 会被 vibrancy 压暗,所以用显式颜色
    static let previewInfo = dynamic(light: lightText.withAlphaComponent(0.7), dark: darkText.withAlphaComponent(0.7))

    // MARK: - 卡片

    /// 卡片底色:浅色纯白,深色是比面板玻璃略亮的 #2C2C30,让卡片"浮"在面板上
    static let cardBackground = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0x2C / 255, green: 0x2C / 255, blue: 0x30 / 255, alpha: 1)
    )

    /// 卡片发丝边:浅色 7% 黑,深色 8% 白
    static let cardBorder = dynamic(light: .black.withAlphaComponent(0.07), dark: .white.withAlphaComponent(0.08))

    static func cardShadow(hovering: Bool) -> NSColor {
        NSColor.black.withAlphaComponent(hovering ? 0.28 : 0.16)
    }

    /// 头部叠加的来源 App 主色。深色模式底色更暗,需要更高的不透明度才看得出来
    static func headerTint(_ color: NSColor) -> NSColor {
        dynamic(light: color.withAlphaComponent(0.14), dark: color.withAlphaComponent(0.24))
    }

    /// 图片卡上浮在图片之上的文字
    static let onImagePrimary = NSColor.white
    static let onImageSecondary = NSColor.white.withAlphaComponent(0.8)

    /// 图片卡头部渐变:顶部 50% 黑渐隐到透明
    static let imageHeaderGradient = (top: NSColor.black.withAlphaComponent(0.5), bottom: NSColor.black.withAlphaComponent(0))

    /// 悬停快捷按钮底色。onDarkSurface 为图片/彩色卡片,用白色半透明
    static func actionButtonFill(onDarkSurface: Bool, highlighted: Bool, pressed: Bool) -> NSColor {
        if onDarkSurface {
            return NSColor.white.withAlphaComponent(pressed ? 0.45 : (highlighted ? 0.35 : 0.25))
        }
        return systemGrayBase.withAlphaComponent(pressed ? 0.42 : (highlighted ? 0.34 : 0.24))
    }

    /// 链接卡的信息块底色
    static let linkBoxFill = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
    /// 链接首字母方块:固定深色底白字,深浅模式下都清晰
    static let linkIconFill = NSColor(srgbRed: 0x24 / 255, green: 0x29 / 255, blue: 0x2F / 255, alpha: 1)
    static let linkIconBorder = NSColor.white.withAlphaComponent(0.15)

    /// 代码高亮
    static let codeKeyword = NSColor.systemOrange
    static let codeString = NSColor.systemGreen

    /// 卡片上的胶囊标签
    static let badgeDarkFill = NSColor.black.withAlphaComponent(0.5)
    static let badgeLightFill = NSColor.white.withAlphaComponent(0.88)

    // MARK: - 置顶

    /// 置顶标记(头部图钉)
    static let pinned = NSColor.systemOrange
    /// 置顶分组底色与描边
    static let pinnedGroupFill = NSColor.systemOrange.withAlphaComponent(0.10)
    static let pinnedGroupBorder = NSColor.systemOrange.withAlphaComponent(0.22)
}
