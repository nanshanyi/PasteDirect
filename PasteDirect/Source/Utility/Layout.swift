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

    // MARK: - 搜索框
    static let searchBarHeight: CGFloat = 30
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
    static let itemBorderWidth: CGFloat = 4
    static let itemTopViewHeight: CGFloat = 60
    static let itemBottomViewHeight: CGFloat = 24
    static let itemBottomOffset: CGFloat = 24
    static let headerFooterSize = NSSize(width: 0, height: itemSize.height)
    static let edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: -20, right: 0)

    // MARK: - 设置按钮
    static let settingButtonSize: CGFloat = 44
    static let settingButtonTrailing: CGFloat = 16

    // MARK: - 筛选弹窗
    static let filterPopoverHeight: CGFloat = 300

    // MARK: - 预览
    static let previewPadding: CGFloat = 24
    static let previewInfoPadding: CGFloat = 56
    static let previewCornerRadius: CGFloat = 16
    static let previewMaxSize: CGFloat = 800
    static let previewMinWidth: CGFloat = 400
    static let previewMinHeight: CGFloat = 240
    static let previewMaxHeight: CGFloat = 400
    static let previewTextInset: CGFloat = 12

    /// 面板高度 = 搜索框顶部间距 + 搜索框 + 列表顶部间距 + item高度 + 列表底部间距
    static var viewHeight: CGFloat {
        searchBarTop + searchBarHeight + scrollViewTop + itemSize.height + scrollViewBottom
    }
}
