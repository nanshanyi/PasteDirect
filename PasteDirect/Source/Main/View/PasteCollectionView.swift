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

/// 横向流式布局。
/// - 置顶折叠条是 section header：收起时悬停在列表左边，卡片从它下面滑过；展开时跟着列表滑走。
/// - 竖条和开头的连续置顶条目身后放一块装饰视图作为分组底色，层级由 zIndex 决定：
///   竖条悬停时底色在卡片上面、竖条下面，其余时候垫在卡片下面。
final class PasteFlowLayout: NSCollectionViewFlowLayout {
    static let pinnedBackgroundKind = "PinnedGroupBackground"
    private static let backgroundIndexPath = IndexPath(item: 0, section: 0)

    /// 返回列表开头连续置顶条目的数量,0 表示不显示分组底色。
    /// 每次布局时主动读取,不依赖外部推送:数据可能在控制器订阅变化之前就已加载。
    var pinnedCountProvider: (() -> Int)?

    /// 列表开头是否有置顶折叠条
    var hasPinRail = false {
        didSet {
            guard hasPinRail != oldValue else { return }
            headerReferenceSize = NSSize(width: hasPinRail ? PinRailHeaderView.width : 0, height: 0)
            updateLeadingInset()
        }
    }

    /// 竖条是否悬停在列表左边（收起时）。
    /// 不用系统的 sectionHeadersPinToVisibleBounds：它会把 header 挪进滚动视图的悬浮容器，
    /// macOS 26 起滚动视图会在悬浮视图下面自动垫一层滚动边缘模糊（NSScrollPocket），且没有公开开关；
    /// header 挪走后布局属性里的位置也不变，底色跟不上。这里自己按可见区域摆 header，它始终留在列表里
    var pinsRail = false {
        didSet {
            guard pinsRail != oldValue else { return }
            updateLeadingInset()
        }
    }

    /// 竖条和第一张卡片的间距由列表左内边距留出（cell 自带 itemShadowMargin 的留白，要减掉）：
    /// 收起时竖条自成一块，和后面的卡片隔开 collapsedGap；
    /// 展开时竖条和置顶卡片在同一块底色里，按设计稿 .pin-cards 的 padding-left 只留 expandedGap
    private static let collapsedGap: CGFloat = 12
    private static let expandedGap: CGFloat = 2

    private func updateLeadingInset() {
        let gap = hasPinRail ? (pinsRail ? Self.collapsedGap : Self.expandedGap) : Layout.lineSpacing
        sectionInset.left = gap - Layout.itemShadowMargin
        invalidateLayout()
    }

    private var isPinningRail: Bool { hasPinRail && pinsRail }

    /// 折叠条收起、鼠标不在上面时底色用淡色
    var dimsPinnedBackground = false {
        didSet {
            guard dimsPinnedBackground != oldValue else { return }
            invalidateBackground()
        }
    }

    override init() {
        super.init()
        register(PinnedGroupBackgroundView.self, forDecorationViewOfKind: Self.pinnedBackgroundKind)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        // header 换成下面算好的（可能已悬停到可见区域左边）：父类按原位置判断是否在 rect 里，
        // 滚远之后会把它漏掉
        var attributes = super.layoutAttributesForElements(in: rect)
            .filter { $0.representedElementKind != NSCollectionView.elementKindSectionHeader }
        if hasPinRail,
           let header = layoutAttributesForSupplementaryView(
               ofKind: NSCollectionView.elementKindSectionHeader, at: Self.backgroundIndexPath),
           header.frame.intersects(rect) {
            attributes.append(header)
        }
        if let background = pinnedBackgroundAttributes(), background.frame.intersects(rect) {
            attributes.append(background)
        }
        return attributes
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        let attributes = super.layoutAttributesForSupplementaryView(ofKind: elementKind, at: indexPath)
        guard elementKind == NSCollectionView.elementKindSectionHeader,
              let copy = attributes?.copy() as? NSCollectionViewLayoutAttributes else { return attributes }
        // 竖条压在卡片和底色上面：悬停时卡片从它下面滑过
        copy.zIndex = 2
        if isPinningRail, let visibleMinX = collectionView?.visibleRect.minX {
            copy.frame.origin.x = max(copy.frame.minX, visibleMinX)
        }
        return copy
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

    // 竖条悬停时，滚动要重新摆它和底色
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        super.shouldInvalidateLayout(forBoundsChange: newBounds) || isPinningRail
    }

    override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard isPinningRail, let collectionView else { return context }
        // 只是滚动、尺寸没变：cell 不用重算，只动竖条和底色
        if newBounds.size == collectionView.bounds.size,
           let flowContext = context as? NSCollectionViewFlowLayoutInvalidationContext {
            flowContext.invalidateFlowLayoutAttributes = false
            flowContext.invalidateFlowLayoutDelegateMetrics = false
        }
        context.invalidateSupplementaryElements(ofKind: NSCollectionView.elementKindSectionHeader, at: [Self.backgroundIndexPath])
        context.invalidateDecorationElements(ofKind: Self.pinnedBackgroundKind, at: [Self.backgroundIndexPath])
        return context
    }

    /// 只重算底色，不动 cell
    private func invalidateBackground() {
        let context = NSCollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutAttributes = false
        context.invalidateFlowLayoutDelegateMetrics = false
        context.invalidateDecorationElements(ofKind: Self.pinnedBackgroundKind, at: [Self.backgroundIndexPath])
        invalidateLayout(with: context)
    }

    /// 底色铺满竖条和开头置顶 cell 的并集;cell 已包含卡片四周留白,所以底色比卡片外扩一圈,
    /// 竖条上下也补到和 cell 一样高。收起时列表里没有置顶 cell,只框住竖条;
    /// 搜索时没有竖条,只框住置顶 cell。展开/收起时它和 cell 一起由布局动画伸缩
    private func pinnedBackgroundAttributes() -> NSCollectionViewLayoutAttributes? {
        var rect: NSRect?
        // 用悬停后的 header 位置，底色和竖条一起走
        if hasPinRail,
           let headerFrame = layoutAttributesForSupplementaryView(
               ofKind: NSCollectionView.elementKindSectionHeader, at: Self.backgroundIndexPath)?.frame {
            rect = PinRailHeaderView.railFrame(in: headerFrame).insetBy(dx: 0, dy: -Layout.itemShadowMargin)
        }
        let itemCount = (collectionView?.numberOfSections ?? 0) > 0 ? collectionView?.numberOfItems(inSection: 0) ?? 0 : 0
        let count = min(pinnedCountProvider?() ?? 0, itemCount)
        if count > 0,
           let first = super.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame,
           let last = super.layoutAttributesForItem(at: IndexPath(item: count - 1, section: 0))?.frame {
            let cells = first.union(last)
            rect = rect.map { $0.union(cells) } ?? cells
        }
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        let attributes = PinnedGroupLayoutAttributes(
            forDecorationViewOfKind: Self.pinnedBackgroundKind,
            with: Self.backgroundIndexPath
        )
        attributes.frame = rect
        // 竖条悬停时底色夹在卡片和竖条之间，卡片从整个竖条下面穿过；其余时候垫在卡片下面
        attributes.zIndex = isPinningRail ? 1 : -1
        attributes.isDimmed = dimsPinnedBackground
        return attributes
    }
}

/// 置顶分组底色的布局属性:多带一个淡色状态,随布局一起交给装饰视图
final class PinnedGroupLayoutAttributes: NSCollectionViewLayoutAttributes {
    /// 竖条收起、鼠标不在上面时用淡色
    var isDimmed = false

    override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone)
        (copy as? PinnedGroupLayoutAttributes)?.isDimmed = isDimmed
        return copy
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PinnedGroupLayoutAttributes, other.isDimmed == isDimmed else { return false }
        return super.isEqual(object)
    }
}

/// 置顶折叠条所在的 section header。header 会被列表回收重建，竖条本身带着状态（图标、悬停、点击），
/// 所以这里只是个空容器，控制器每次取 header 时把同一个竖条放进来
final class PinRailHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("PinRailHeader")
    /// 竖条离面板左边的距离，和底色离面板底边的距离一样：
    /// 底色上下铺满列表，列表底边离面板底边 scrollViewBottom − itemShadowMargin = 8
    static let railMinX = Layout.scrollViewBottom - Layout.itemShadowMargin
    static let width = railMinX + PastePinRailView.width

    /// 竖条在 header 里的位置：上下和卡片对齐（cell 上下各有 itemShadowMargin 的留白）
    static func railFrame(in headerFrame: NSRect) -> NSRect {
        NSRect(x: headerFrame.minX + railMinX, y: headerFrame.minY + Layout.itemShadowMargin,
               width: PastePinRailView.width, height: max(0, headerFrame.height - Layout.itemShadowMargin * 2))
    }

    func embed(_ rail: NSView) {
        guard rail.superview !== self else { return }
        rail.removeFromSuperview()
        rail.translatesAutoresizingMaskIntoConstraints = true
        rail.autoresizingMask = [.height]
        rail.frame = Self.railFrame(in: bounds)
        addSubview(rail)
    }

    override func layout() {
        super.layout()
        if let rail = subviews.first { rail.frame = Self.railFrame(in: bounds) }
    }

    // 竖条左边那段空白不挡点击，悬停时下面的卡片还能点到
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
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
        // 底色按 cell 的 frame 铺,四周比卡片大出 itemShadowMargin,
        // 圆角取卡片圆角加上这段距离(18 + 8 = 26),和卡片同心
        layer.cornerRadius = Layout.itemCornerRadius + Layout.itemShadowMargin
        layer.cornerCurve = .continuous
        let fillColor = (isDimmed ? AppColor.pinnedGroupFillDimmed : AppColor.pinnedGroupFill).cgColor
        let border = (isDimmed ? AppColor.pinnedGroupBorderDimmed : AppColor.pinnedGroupBorder).cgColor
        if animatesNextColorChange {
            animatesNextColorChange = false
            // 设计稿 .pin-rail 的 transition: background .15s
            for (key, value) in [("backgroundColor", fillColor), ("borderColor", border)] {
                let animation = CABasicAnimation(keyPath: key)
                animation.fromValue = layer.value(forKey: key)
                animation.toValue = value
                animation.duration = 0.15
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: key)
            }
        }
        layer.backgroundColor = fillColor
        layer.borderColor = border
        layer.borderWidth = 1
    }

    func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        isDimmed = (layoutAttributes as? PinnedGroupLayoutAttributes)?.isDimmed ?? false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


