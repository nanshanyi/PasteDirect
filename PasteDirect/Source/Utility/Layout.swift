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
    /// 顶部可拖拽调整高度的区域(把手在其中居中)
    static let resizeHandleHeight: CGFloat = 14

    // MARK: - 面板高度限制
    static let defaultViewHeight: CGFloat = 280
    static let minViewHeight: CGFloat = defaultViewHeight - 30
    static let maxViewHeight: CGFloat = defaultViewHeight + 70

    // MARK: - 搜索框
    static let searchBarHeight: CGFloat = 26
    static let searchBarWidth: CGFloat = 400
    static let searchBarTop: CGFloat = 16

    // MARK: - 列表
    static let scrollViewTop: CGFloat = 16
    static let scrollViewBottom: CGFloat = 16
    /// 卡片之间的视觉间距
    static let lineSpacing: CGFloat = 20
    static let padding: CGFloat = 20

    // MARK: - Item
    static let itemCornerRadius: CGFloat = 18
    /// 选中描边宽度,画在卡片外圈
    static let itemBorderWidth: CGFloat = 2.5
    /// 选中描边与卡片之间的间隙
    static let itemRingGap: CGFloat = 4
    static let itemHeaderHeight: CGFloat = 36
    /// 卡片内容左右内边距
    static let itemInset: CGFloat = 12
    /// 卡片在 cell 内四周的留白:容纳阴影、选中外圈和悬停上浮,避免被裁切。
    static let itemShadowMargin: CGFloat = 8
    /// 悬停时卡片上浮的距离
    static let itemHoverLift: CGFloat = 3

    // MARK: - 设置按钮
    /// 设置按钮:28pt 点击区域,图标 13pt(与设计稿一致)
    static let settingButtonSize: CGFloat = 28
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
        // cell = 卡片 + 四周留白,cell 内卡片再内缩回正方形
        return NSSize(width: cardSide + itemShadowMargin * 2, height: cardSide + itemShadowMargin * 2)
    }

    /// 卡片默认边长(面板默认高度时),作为各元素按高度缩放的基准
    static let baseCardSide: CGFloat = defaultViewHeight - searchBarTop - searchBarHeight - scrollViewTop - scrollViewBottom

    /// 按卡片高度等比缩放某个基准尺寸,并限制在给定范围内
    static func scaled(_ base: CGFloat, for cardHeight: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(base * cardHeight / baseCardSide, range.lowerBound), range.upperBound)
    }
}
