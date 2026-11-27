//
//  PastePinRailView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/11/26.
//

import AppKit
import SnapKit

/// 置顶折叠条：固定在列表左侧的窄条，收起时置顶项只在这里显示图钉、竖排「置顶」、数量和来源 App 图标，
/// 让最近复制的条目始终从第一张卡开始。点击展开/收起，悬停弹出置顶清单。
/// 底色不在这里画：收起和展开都是同一块 PinnedGroupBackgroundView，只是宽窄不同。
final class PastePinRailView: NSView {
    static let width: CGFloat = 56
    /// 折叠条与第一张卡片之间的距离
    static let gap: CGFloat = 12
    private static let maxAppIcons = 6
    private static let appIconSize: CGFloat = 22
    /// 相邻图标叠压的高度，约一半，露出的部分足够认出是哪个 App
    private static let iconOverlap: CGFloat = 10
    /// 条目之间的统一间距（设计稿 gap: 10px）
    /// 箭头离竖条底边的距离（设计稿 padding-bottom: 10px）
    private static let spacing: CGFloat = 10
    /// 图钉、「置顶」、数量、图标区、箭头之间的间距，比设计稿的 10 收紧，竖条里能多放几个图标
    private static let itemSpacing: CGFloat = 6

    var onClick: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private var isPressed = false
    /// 去重后的来源 App 路径，高度变化时据此重算能放几个图标
    private var iconPaths: [String] = []
    /// 当前实际放进去的图标对应的 App 路径，数量或内容变了才重建
    private var shownIconPaths: [String]?
    /// 上一次配置的是展开还是收起，nil 表示还没配置过（首次不做动画）
    private var appliedExpanded: Bool?
    /// 图钉的垂直中心到顶部的距离，跟着卡片头部高度变
    private var pinCenterConstraint: Constraint?
    /// 上次配置时的置顶数量，变多时徽章跳一下
    private var pinnedCount = 0
    /// 图标栈里已有的图标，按 App 路径复用：增删时只动变化的那几个，留下的平移到新位置
    private var iconViews: [String: NSImageView] = [:]
    /// 这次重排图标要不要带动画（只在 configure 里、新置顶到来时打开）
    private var animatesIconChange = false

    private let pinView = NSImageView().then {
        $0.image = CardIcon.pinFilled.image
        $0.contentTintColor = AppColor.pinned
        // 与卡片右上角的图钉同一张图、同样不缩放，两处大小一致
        $0.imageScaling = .scaleNone
    }

    /// 竖排「置顶」：设计稿用 writing-mode: vertical-rl，这里逐字换行模拟，行高按 11 + 0.12em 收紧
    private let titleLabel = NSlabel().then {
        $0.alignment = .center
        $0.maximumNumberOfLines = 2
        $0.lineBreakMode = .byClipping
        $0.drawsBackground = false
        $0.attributedStringValue = PastePinRailView.titleText
    }

    /// 数量胶囊：橙底白字，高 14 时圆角 7 即为胶囊（设计稿 border-radius: 8 会被高度夹到一半）
    private let badgeView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.cornerRadius = 7
        $0.layer?.cornerCurve = .continuous
        $0.layer?.backgroundColor = AppColor.pinned.cgColor
    }

    private let countLabel = NSlabel().then {
        $0.font = .systemFont(ofSize: 10, weight: .bold)
        $0.textColor = .white
        $0.alignment = .center
        $0.drawsBackground = false
    }

    private let appStack = NSStackView().then {
        $0.orientation = .vertical
        $0.alignment = .centerX
        // 图标上下叠压，像一摞卡片
        $0.spacing = -PastePinRailView.iconOverlap
    }

    private let chevronView = RotatingChevronView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(pinView)
        addSubview(titleLabel)
        addSubview(badgeView)
        badgeView.addSubview(countLabel)
        addSubview(appStack)
        addSubview(chevronView)

        pinView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            // 竖条和卡片上下对齐、一样高，图钉放在卡片头部的中线上，和卡片里的图钉在一条横线
            pinCenterConstraint = make.centerY.equalTo(self.snp.top).offset(Layout.itemHeaderHeight / 2).constraint
            make.size.equalTo(CardIcon.pinFilled.image.size)
        }
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(pinView.snp.bottom).offset(Self.itemSpacing)
        }
        badgeView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(Self.itemSpacing)
            make.height.equalTo(14)
        }
        countLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(6)
            make.centerY.equalToSuperview()
        }
        chevronView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-Self.spacing)
            make.width.height.equalTo(12)
        }
        // 图标栈靠底：设计稿给它的 margin-top: auto
        appStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(chevronView.snp.top).offset(-Self.itemSpacing)
            make.top.greaterThanOrEqualTo(badgeView.snp.bottom).offset(Self.itemSpacing)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// animated 为 false 时直接到位（如面板打开前回到默认展开状态）
    func configure(items: [PasteboardModel], expanded: Bool, animated: Bool = true) {
        countLabel.stringValue = "\(items.count)"
        toolTip = expanded ? String(localized: "Hide Pinned") : String(localized: "Show Pinned")
        // 首次配置直接到位，之后的状态切换才做动画，免得启动时闪一下
        let animated = animated && appliedExpanded != nil
        appliedExpanded = expanded
        applyExpandedAppearance(expanded, animated: animated)

        var seen = Set<String>()
        let paths = Array(items.map(\.appPath).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.maxAppIcons))
        // 只在收起、面板可见时做动画：展开时图标栈是隐藏的，面板没显示时用户也看不到
        let showsChange = animated && !expanded && window?.isVisible == true
        if showsChange, items.count > pinnedCount {
            Self.pop(badgeView, from: 1.25, spring: false)
        }
        pinnedCount = items.count
        iconPaths = paths
        animatesIconChange = showsChange
        updateIconLayout()
        animatesIconChange = false
    }

    /// 展开时图标栈淡出、箭头转 180°（设计稿 .2s / .25s）；图标栈用透明度而不是 isHidden，
    /// 淡出期间还占着位置，箭头不会提前往下跳
    private func applyExpandedAppearance(_ expanded: Bool, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                appStack.animator().alphaValue = expanded ? 0 : 1
            }
        } else {
            appStack.alphaValue = expanded ? 0 : 1
        }
        rotateChevron(expanded: expanded, animated: animated)
    }

    private func rotateChevron(expanded: Bool, animated: Bool) {
        chevronView.setAngle(expanded ? .pi : 0, animated: animated)
    }

    override func layout() {
        pinCenterConstraint?.update(offset: Layout.itemHeaderHeight(for: bounds.height) / 2)
        super.layout()
        // 面板高度会变，竖条变矮时按剩余空间减少图标数量，避免和标题、徽章挤在一起
        updateIconLayout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        badgeView.layer?.backgroundColor = resolvedCGColor(AppColor.pinned)
    }

    /// 动态颜色按当前外观取值：layer 上的 CGColor 不会跟着深浅色自己变
    private func resolvedCGColor(_ color: NSColor) -> CGColor {
        var cgColor: CGColor = .clear
        effectiveAppearance.performAsCurrentDrawingAppearance { cgColor = color.cgColor }
        return cgColor
    }

    /// 按徽章和箭头之间实际留出的高度决定能放几个图标，不再手算各段高度（标题高度随文案变）。
    /// 第一个图标占满 22，之后每个只多占 22 − 叠压
    private func updateIconLayout() {
        guard bounds.height > 0 else { return }
        // 非翻转坐标：徽章在上，minY 是它的下边缘；箭头在下，maxY 是它的上边缘
        let room = badgeView.frame.minY - chevronView.frame.maxY - Self.itemSpacing * 2
        let step = Self.appIconSize - Self.iconOverlap
        let limit = room < Self.appIconSize ? 0 : min(Self.maxAppIcons, 1 + Int((room - Self.appIconSize) / step))
        let paths = Array(iconPaths.prefix(limit))
        guard paths != shownIconPaths else { return }
        shownIconPaths = paths
        let animated = animatesIconChange
        // 改动前每个位置上图标的 frame，新图标从它所在位置原来那张图标处出发
        let oldFrames = appStack.arrangedSubviews.map(\.frame)

        // 不再显示的：移出图标栈。带动画时留在原处淡出再移除，不占图标栈的位置
        for (path, icon) in iconViews where !paths.contains(path) {
            iconViews[path] = nil
            appStack.removeArrangedSubview(icon)
            guard animated else {
                icon.removeFromSuperview()
                continue
            }
            // 离开图标栈后没有约束定位，改回按 frame 摆放，停在原地
            icon.translatesAutoresizingMaskIntoConstraints = true
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                icon.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { icon.removeFromSuperview() }
            }
        }

        var arriving: [NSView] = []
        for (index, path) in paths.enumerated() {
            if let icon = iconViews[path] {
                // 已有的图标换了位置：挪过去，frame 保留，下面的布局动画从旧位置平移过去
                if appStack.arrangedSubviews.firstIndex(of: icon) != index {
                    appStack.removeArrangedSubview(icon)
                    appStack.insertArrangedSubview(icon, at: index)
                }
                continue
            }
            let icon = Self.makeIcon(path: path)
            if animated {
                // 没有起始 frame 时布局动画会让它从左下角 (0,0) 飞过来
                icon.frame = index < oldFrames.count ? oldFrames[index] : oldFrames.last ?? .zero
                icon.alphaValue = 0
                arriving.append(icon)
            }
            iconViews[path] = icon
            appStack.insertArrangedSubview(icon, at: index)
        }
        // 下面的图标盖住上面的（和设计稿一致）。插入会打乱子视图的前后顺序，用 zPosition 统一
        for (index, icon) in appStack.arrangedSubviews.enumerated() {
            icon.layer?.zPosition = CGFloat(index)
        }

        guard animated else { return }
        // 留下的图标平移到新位置，新图标同时弹出来
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
        }
        for icon in arriving {
            icon.alphaValue = 1
            Self.pop(icon, from: 0.5, spring: true)
            Self.fadeIn(icon)
        }
    }

    private static func makeIcon(path: String) -> NSImageView {
        let icon = NSImageView().then {
            $0.image = NSWorkspace.shared.icon(forFile: path)
            $0.imageScaling = .scaleProportionallyUpOrDown
            $0.wantsLayer = true
        }
        icon.snp.makeConstraints { make in make.width.height.equalTo(appIconSize) }
        return icon
    }

    /// 绕中心缩放的动画。视图自带的 layer 锚点在左下角，直接缩放会往左下角缩，
    /// 所以把「平移到中心 → 缩放 → 平移回去」合成一个变换来做
    private static func pop(_ view: NSView, from scale: CGFloat, spring: Bool) {
        view.wantsLayer = true
        guard let layer = view.layer, layer.bounds.width > 0 else { return }
        let size = layer.bounds.size
        var start = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        start = CATransform3DScale(start, scale, scale, 1)
        start = CATransform3DTranslate(start, -size.width / 2, -size.height / 2, 0)
        let animation: CABasicAnimation
        if spring {
            // 带一点回弹：像一张卡片落到这摞上
            let springAnimation = CASpringAnimation(keyPath: "transform")
            springAnimation.damping = 12
            springAnimation.stiffness = 260
            springAnimation.duration = springAnimation.settlingDuration
            animation = springAnimation
        } else {
            animation = CABasicAnimation(keyPath: "transform")
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        animation.fromValue = start
        animation.toValue = CATransform3DIdentity
        layer.add(animation, forKey: "pop")
    }

    private static func fadeIn(_ view: NSView) {
        guard let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 0.18
        layer.add(animation, forKey: "fadeIn")
    }

    /// 竖排标题:中文按字换行模拟 writing-mode: vertical-rl,英文等较长文案保持横排
    private static let titleText: NSAttributedString = {
        let text = String(localized: "Pin")
        let stacked = text.count <= 2 ? text.map(String.init).joined(separator: "\n") : text
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // 11pt + 0.12em 字距 ≈ 行高 12.3,取 13
        paragraph.minimumLineHeight = 13
        paragraph.maximumLineHeight = 13
        return NSAttributedString(string: stacked, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: AppColor.pinned,
            .paragraphStyle: paragraph,
        ])
    }()

    // MARK: - 鼠标

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isPressed = false
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if isPressed && inside { onClick?() }
        isPressed = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 悬停预览

/// 折叠条旁弹出的置顶清单：每行来源 App + 内容摘要 + ⌥ 编号，点一行直接粘贴
final class PastePinPeekViewController: NSViewController {
    static let width: CGFloat = 280
    private static let rowHeight: CGFloat = 30
    private static let maxRows = 9
    private static let inset: CGFloat = 6

    var onSelect: ((PasteboardModel) -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private let stack = NSStackView().then {
        $0.orientation = .vertical
        $0.alignment = .leading
        $0.spacing = 0
    }

    override func loadView() {
        let root = HoverTrackingView()
        root.onHoverChange = { [weak self] in self?.onHoverChange?($0) }
        root.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Self.inset)
        }
        view = root
    }

    func configure(items: [PasteboardModel]) {
        _ = view
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let shown = Array(items.prefix(Self.maxRows))
        for (index, model) in shown.enumerated() {
            let row = PinPeekRow(model: model, number: index + 1)
            row.onClick = { [weak self] in self?.onSelect?(model) }
            stack.addArrangedSubview(row)
            row.snp.makeConstraints { make in
                make.width.equalTo(Self.width - Self.inset * 2)
                make.height.equalTo(Self.rowHeight)
            }
        }
        let footer = NSlabel().then {
            $0.stringValue = items.count > Self.maxRows
                ? String(localized: "Click the pinned bar to show all \(items.count)")
                : String(localized: "Click the pinned bar to show all")
            $0.font = .systemFont(ofSize: 11)
            $0.textColor = .secondaryLabelColor
            $0.drawsBackground = false
        }
        let footerWrap = NSView()
        footerWrap.addSubview(footer)
        footer.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
        }
        stack.addArrangedSubview(footerWrap)
        footerWrap.snp.makeConstraints { make in
            make.width.equalTo(Self.width - Self.inset * 2)
            make.height.equalTo(26)
        }
        preferredContentSize = NSSize(width: Self.width,
                                      height: CGFloat(shown.count) * Self.rowHeight + 26 + Self.inset * 2)
    }
}

/// 清单里的一行
private final class PinPeekRow: NSView {
    var onClick: (() -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }

    init(model: PasteboardModel, number: Int) {
        super.init(frame: .zero)
        wantsLayer = true

        let icon = NSImageView()
        icon.image = model.appPath.isEmpty ? nil : NSWorkspace.shared.icon(forFile: model.appPath)
        let title = NSlabel().then {
            $0.stringValue = Self.summary(of: model)
            $0.font = .systemFont(ofSize: 12)
            $0.textColor = .labelColor
            $0.lineBreakMode = .byTruncatingTail
            $0.maximumNumberOfLines = 1
            $0.drawsBackground = false
            $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let key = NSlabel().then {
            $0.stringValue = "⌥\(number)"
            $0.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            $0.textColor = .tertiaryLabelColor
            $0.drawsBackground = false
        }
        addSubview(icon)
        addSubview(title)
        addSubview(key)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(18)
        }
        key.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalToSuperview()
        }
        title.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualTo(key.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 单行摘要：文字取第一行非空内容，图片显示尺寸，颜色显示色值
    private static func summary(of model: PasteboardModel) -> String {
        switch model.type {
        case .image:
            let size = model.sizeString()
            return size.isEmpty ? String(localized: "Image") : "\(String(localized: "Image")) · \(size)"
        case .color:
            return model.hexColorString ?? model.dataString
        default:
            let line = model.dataString
                .split(whereSeparator: \.isNewline)
                .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return line ?? model.type.string
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.backgroundColor = isHovered ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 箭头

/// 展开时整体转 180° 的箭头（设计稿 transform: rotate(180deg) .25s），而不是换一个朝左的符号。
/// 旋转放在自己建的 sublayer 上：视图自身的 layer 归 AppKit 管，anchorPoint 是左下角，
/// 转 180° 会甩到视图外面，而且每次重新布局 AppKit 都会把它的 transform 复位
private final class RotatingChevronView: NSView {
    private let glyphLayer = CALayer()
    private let maskLayer = CALayer()
    private var angle: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        maskLayer.contentsGravity = .center
        glyphLayer.mask = maskLayer
        layer?.addSublayer(glyphLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    /// 符号只当遮罩，颜色由底色给：深浅色切换时只要重设颜色
    override func updateLayer() {
        glyphLayer.backgroundColor = NSColor.tertiaryLabelColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 独立的 CALayer 默认绕中心转，只改 bounds/position，不会动到 transform
        glyphLayer.bounds = bounds
        glyphLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        maskLayer.frame = glyphLayer.bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        maskLayer.contentsScale = scale
        maskLayer.contents = image?.layerContents(forContentsScale: scale)
    }

    func setAngle(_ newAngle: CGFloat, animated: Bool) {
        guard newAngle != angle else { return }
        if animated {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = angle
            animation.toValue = newAngle
            animation.duration = 0.25
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glyphLayer.add(animation, forKey: "rotation")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.transform = CATransform3DMakeRotation(newAngle, 0, 0, 1)
        CATransaction.commit()
        angle = newAngle
    }
}
