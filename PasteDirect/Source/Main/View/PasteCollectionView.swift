//
//  PasteCollectionView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/4/11.
//

import Carbon
import Cocoa

@MainActor
protocol PasteCollectionViewKeyDelegate: AnyObject {
    func collectionViewDidPressDelete()
    func collectionViewDidPressReturn()
    func collectionViewDidPressSpace()
    func collectionViewDidPressEscape()
}

final class PasteCollectionView: NSCollectionView {
    weak var keyDelegate: PasteCollectionViewKeyDelegate?

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Delete:
            keyDelegate?.collectionViewDidPressDelete()
        case kVK_Return:
            keyDelegate?.collectionViewDidPressReturn()
        case kVK_Space:
            keyDelegate?.collectionViewDidPressSpace()
        case kVK_Escape:
            keyDelegate?.collectionViewDidPressEscape()
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - 布局

/// 横向流式布局,在列表开头的连续置顶条目身后放一块装饰视图作为分组底色。
final class PasteFlowLayout: NSCollectionViewFlowLayout {
    static let pinnedBackgroundKind = "PinnedGroupBackground"

    /// 返回列表开头连续置顶条目的数量,0 表示不显示分组底色。
    /// 每次布局时主动读取,不依赖外部推送:数据可能在控制器订阅变化之前就已加载。
    var pinnedCountProvider: (() -> Int)?
    /// 折叠条展开时,这块底色由外层统一容器绘制(它要连竖条一起包住),这里关掉避免两层圆角叠在一起
    var showsPinnedBackground = true

    override init() {
        super.init()
        register(PinnedGroupBackgroundView.self, forDecorationViewOfKind: Self.pinnedBackgroundKind)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var attributes = super.layoutAttributesForElements(in: rect)
        if let background = pinnedBackgroundAttributes(), background.frame.intersects(rect) {
            attributes.append(background)
        }
        return attributes
    }

    override func layoutAttributesForDecorationView(
        ofKind elementKind: NSCollectionView.DecorationElementKind,
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        guard elementKind == Self.pinnedBackgroundKind else {
            return super.layoutAttributesForDecorationView(ofKind: elementKind, at: indexPath)
        }
        return pinnedBackgroundAttributes()
    }

    /// 底色铺满置顶 cell 的并集;cell 已包含卡片四周留白,所以底色比卡片外扩一圈
    private func pinnedBackgroundAttributes() -> NSCollectionViewLayoutAttributes? {
        guard showsPinnedBackground else { return nil }
        let itemCount = (collectionView?.numberOfSections ?? 0) > 0 ? collectionView?.numberOfItems(inSection: 0) ?? 0 : 0
        let count = min(pinnedCountProvider?() ?? 0, itemCount)
        guard count > 0,
              let first = super.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame,
              let last = super.layoutAttributesForItem(at: IndexPath(item: count - 1, section: 0))?.frame
        else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(
            forDecorationViewOfKind: Self.pinnedBackgroundKind,
            with: IndexPath(item: 0, section: 0)
        )
        attributes.frame = first.union(last)
        attributes.zIndex = -1
        return attributes
    }
}

/// 置顶分组背景:系统橙 22% 填充 + 45% 描边
final class PinnedGroupBackgroundView: NSView, NSCollectionViewElement {
    /// 折叠条收起、鼠标不在上面时用淡色；鼠标移上去加深到常规色
    var isDimmed = false {
        didSet {
            guard isDimmed != oldValue else { return }
            animatesNextColorChange = true
            needsDisplay = true
        }
    }
    private var animatesNextColorChange = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        // 圆角从面板向内推:底色底边离面板 8pt,26 − 8 = 18,底面与面板左下角同心。
        // 这个值同时等于卡片圆角,折叠成 56pt 竖条时也还是设计稿的圆角矩形
        layer.cornerRadius = Layout.itemCornerRadius
        layer.cornerCurve = .continuous
        let fill = (isDimmed ? AppColor.pinnedGroupFillDimmed : AppColor.pinnedGroupFill).cgColor
        let border = (isDimmed ? AppColor.pinnedGroupBorderDimmed : AppColor.pinnedGroupBorder).cgColor
        if animatesNextColorChange {
            animatesNextColorChange = false
            // 设计稿 .pin-rail 的 transition: background .15s
            for (key, value) in [("backgroundColor", fill), ("borderColor", border)] {
                let animation = CABasicAnimation(keyPath: key)
                animation.fromValue = layer.value(forKey: key)
                animation.toValue = value
                animation.duration = 0.15
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: key)
            }
        }
        layer.backgroundColor = fill
        layer.borderColor = border
        layer.borderWidth = 1
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


