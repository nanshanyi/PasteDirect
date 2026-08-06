//
//  Layout.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import Foundation

enum Layout {
    // MARK: - 屏幕 & 面板
    static let screenPadding: CGFloat = 6
    static let cornerRadius: CGFloat = 32
    static let resizeHandleHeight: CGFloat = 8

    // MARK: - 面板高度限制
    static let defaultViewHeight: CGFloat = 280
    static let compactItemHeight: CGFloat = defaultViewHeight - searchBarTop - searchBarHeight - scrollViewTop - scrollViewBottom
    static let minViewHeight: CGFloat = defaultViewHeight - 30
    static let maxViewHeight: CGFloat = defaultViewHeight + 70

    // MARK: - 搜索框
    static let searchBarHeight: CGFloat = 26
    static let searchBarWidth: CGFloat = 400
    static let searchBarTop: CGFloat = 16

    // MARK: - 列表
    static let scrollViewTop: CGFloat = 16
    static let scrollViewBottom: CGFloat = 16
    static let lineSpacing: CGFloat = 20
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20

    // MARK: - Item
    static let itemSize = NSSize(width: 260, height: 260)
    static let itemCornerRadius: CGFloat = 16
    static let itemBorderWidth: CGFloat = 3
    static let itemTopViewHeight: CGFloat = 60
    static let itemBottomViewHeight: CGFloat = 24
    static let itemBottomOffset: CGFloat = 24
    /// 卡片上下内缩留白,给阴影(blur+offset)留出不被 scrollView 垂直裁切的空间。
    /// 仅上下:水平滚动列表只在垂直方向裁切,左右贴边由 lineSpacing 控制间距。
    static let itemShadowMargin: CGFloat = 6
    static let headerFooterSize = NSSize(width: 0, height: itemSize.height)
    static let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: -20, right: 0)

    // MARK: - 设置按钮
    static let settingButtonSize: CGFloat = 30
    static let settingButtonTrailing: CGFloat = 16

    // MARK: - 筛选弹窗
    static let filterPopoverHeight: CGFloat = 300

    // MARK: - 预览
    static let previewPadding: CGFloat = 12
    static let previewInfoPadding: CGFloat = 44
    static let previewCornerRadius: CGFloat = 16
    static let previewMaxWidth: CGFloat = 1100
    static let previewMinWidth: CGFloat = 400
    static let previewMinHeight: CGFloat = 240
    static let previewMaxHeight: CGFloat = 800
    static let previewTextInset: CGFloat = 12

    // MARK: - 动态高度

    @MainActor
    static var viewHeight: CGFloat {
        let saved = CGFloat(PasteUserDefaults.panelHeight)
        if saved > 0 {
            return min(max(saved, minViewHeight), maxViewHeight)
        }
        return defaultViewHeight
    }

    static func dynamicItemSize(for height: CGFloat) -> NSSize {
        // 卡片边长(正方形),与未加阴影留白前保持一致
        let cardSide = height - searchBarTop - searchBarHeight - scrollViewTop - scrollViewBottom
        // cell 宽 = 卡片宽(左右贴边);cell 高 = 卡片高 + 上下阴影留白,cell 内卡片再内缩回正方形
        return NSSize(width: cardSide, height: cardSide + itemShadowMargin * 2)
    }

    static func dynamicTopViewHeight(for itemHeight: CGFloat) -> CGFloat {
        let height = itemHeight * 60 / 260
        return min(max(height, 40), 60)
    }

    static func dynamicTypeFontSize(for itemHeight: CGFloat) -> CGFloat {
        let size = itemHeight * 18 / 260
        return min(max(size, 14), 18)
    }

    /// 置顶徽章尺寸随 item 高度缩放(基准 26pt @ 260),小面板时同比缩小
    static func dynamicPinBadgeSize(for itemHeight: CGFloat) -> CGFloat {
        let size = itemHeight * 26 / 260
        return min(max(size, 16), 26)
    }
}
