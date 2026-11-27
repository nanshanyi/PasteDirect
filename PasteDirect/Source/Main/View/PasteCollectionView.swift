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
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Layout.itemCornerRadius + Layout.itemShadowMargin
        layer.cornerCurve = .continuous
        layer.backgroundColor = AppColor.pinnedGroupFill.cgColor
        layer.borderColor = AppColor.pinnedGroupBorder.cgColor
        layer.borderWidth = 1
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


