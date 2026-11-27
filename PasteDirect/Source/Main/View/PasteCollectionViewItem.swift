//
//  PasteCollectionViewItem.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit
import SnapKit

@MainActor
protocol PasteCollectionViewItemDelegate: NSObjectProtocol {
    func deleteItem(_ item: PasteboardModel, indexPath: IndexPath)
    func previewItem(_ item: PasteboardModel, relativeTo view: NSView)
    func pasteItem(_ item: PasteboardModel, isOriginal: Bool)
    func copyItem(_ item: PasteboardModel)
    func copyOCRText(_ item: PasteboardModel)
    func pasteOCRText(_ item: PasteboardModel)
    func togglePin(_ item: PasteboardModel)
}

let maxLength = 300

/// 卡片设计("内容优先"):
/// - 头部是一条轻量信息栏:来源 App 图标 + 名称 + 时间,底色只叠一层很淡的 App 主色
/// - 内容按类型排版:短文本放大、链接突出域名、代码等宽高亮、长文本按词换行
/// - 图片铺满卡片,头部以渐变浮在图上;颜色卡整张即色板
/// - 选中:卡片外圈强调色描边;悬停:阴影加深 + 头部出现置顶/删除;按住 ⌘ 显示快速粘贴编号
final class PasteCollectionViewItem: NSCollectionViewItem {
    weak var delegate: PasteCollectionViewItemDelegate?
    private var pModel: PasteboardModel?
    private var isHovering = false
    private var headerHeightConstraint: NSLayoutConstraint?
    private var appIconSizeConstraints: [NSLayoutConstraint] = []
    private var cardTopConstraint: NSLayoutConstraint?
    private var cardBottomConstraint: NSLayoutConstraint?

    /// 卡片底色语境,决定头部/底部文字颜色
    private enum Surface {
        case standard          // 系统文本背景
        case custom(NSColor)   // 富文本自带底色 / 颜色卡片
        case image             // 图片铺满
    }
    private var surface: Surface = .standard

    // MARK: 卡片骨架

    private lazy var ringView = CardLayerView().then {
        $0.cornerRadius = Layout.itemCornerRadius + Layout.itemRingGap
        $0.borderWidth = Layout.itemBorderWidth
        $0.borderColor = .controlAccentColor
        $0.isHidden = true
    }

    private lazy var cardView = CardLayerView().then {
        $0.cornerRadius = Layout.itemCornerRadius
        $0.clipsContent = true
        $0.fillColor = AppColor.cardBackground
        $0.borderWidth = 0.5
        $0.borderColor = AppColor.cardBorder
    }

    // MARK: 头部

    private lazy var headerView = CardLayerView()

    /// 图片卡头部的深色渐变,保证白字可读
    private lazy var headerGradient = GradientView().then {
        $0.isHidden = true
    }

    private lazy var appIconView = NSImageView().then {
        $0.imageScaling = .scaleProportionallyUpOrDown
    }

    private lazy var appNameLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.lineBreakMode = .byTruncatingTail
        $0.font = .systemFont(ofSize: 12, weight: .semibold)
        $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private lazy var timeLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
        $0.setContentHuggingPriority(.required, for: .horizontal)
    }

    private lazy var pinMark = NSImageView().then {
        // 与悬停按钮里的图钉同一张图,悬停前后大小一致
        $0.image = CardIcon.pinFilled.image
        $0.imageScaling = .scaleNone
        $0.contentTintColor = AppColor.pinned
        $0.isHidden = true
        $0.setContentHuggingPriority(.required, for: .horizontal)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private lazy var pinButton = CardActionButton(icon: .pin, toolTip: String(localized: "Pin")).then {
        $0.target = self
        $0.action = #selector(togglePinClick)
    }

    private lazy var deleteButton = CardActionButton(icon: .trash, toolTip: String(localized: "Delete")).then {
        $0.target = self
        $0.action = #selector(deleteItem)
    }

    private lazy var actionStack = NSStackView(views: [pinButton, deleteButton]).then {
        $0.orientation = .horizontal
        $0.alignment = .centerY
        $0.spacing = 6
        $0.isHidden = true
    }

    // MARK: 文本内容

    private lazy var contentLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 0
        $0.lineBreakMode = .byWordWrapping
        $0.cell?.wraps = true
        $0.cell?.truncatesLastVisibleLine = true
        $0.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    // MARK: 链接内容

    private lazy var linkBox = CardLayerView().then {
        $0.cornerRadius = 12
        $0.fillColor = AppColor.linkBoxFill
        $0.isHidden = true
    }

    /// 链接首字母方块:固定深色底白字,深浅模式下都清晰
    private lazy var linkIcon = CardLayerView().then {
        $0.cornerRadius = 7
        $0.fillColor = AppColor.linkIconFill
        $0.borderWidth = 0.5
        $0.borderColor = AppColor.linkIconBorder
    }

    private lazy var linkIconLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.alignment = .center
        $0.textColor = .white
        $0.font = .systemFont(ofSize: 13, weight: .heavy)
    }

    private lazy var linkHostLabel = NSlabel().then {
        $0.backgroundColor = .clear
        // 单行;长域名在 setStringItem 里缩小字号,仍放不下时中间省略
        $0.maximumNumberOfLines = 1
        $0.lineBreakMode = .byTruncatingMiddle
        $0.textColor = .linkColor
        $0.font = .systemFont(ofSize: 15, weight: .semibold)
    }

    private lazy var linkURLLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 3
        $0.lineBreakMode = .byCharWrapping
        $0.cell?.truncatesLastVisibleLine = true
        $0.textColor = .secondaryLabelColor
        $0.font = .systemFont(ofSize: 11)
        $0.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    // MARK: 颜色内容

    private lazy var hexLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .monospacedSystemFont(ofSize: 24, weight: .bold)
    }

    private lazy var rgbLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    }

    /// 明暗色阶:3 级浅 + 原色 + 2 级深
    private static let swatchSteps: [CGFloat] = [-0.75, -0.5, -0.25, 0, 0.25, 0.5]
    private lazy var swatchViews: [CardLayerView] = Self.swatchSteps.map { _ in
        CardLayerView().then { $0.cornerRadius = 4 }
    }

    private lazy var colorStack = NSStackView().then { stack in
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        let swatchRow = NSStackView(views: swatchViews)
        swatchRow.orientation = .horizontal
        swatchRow.distribution = .fillEqually
        swatchRow.spacing = 4
        swatchRow.snp.makeConstraints { make in make.height.equalTo(14) }
        stack.addArrangedSubview(hexLabel)
        stack.addArrangedSubview(rgbLabel)
        stack.addArrangedSubview(swatchRow)
        stack.setCustomSpacing(10, after: rgbLabel)
        swatchRow.snp.makeConstraints { make in make.width.equalTo(stack) }
        stack.isHidden = true
    }

    // MARK: 图片内容

    private lazy var imageFillView = AspectFillImageView().then {
        $0.isHidden = true
    }

    private lazy var imageSizeBadge = CardBadge(style: .dark)
    private lazy var ocrBadge = CardBadge(style: .light)

    private lazy var imageBadgeStack = NSStackView(views: [imageSizeBadge, ocrBadge]).then {
        $0.orientation = .horizontal
        $0.spacing = 6
        $0.isHidden = true
    }

    // MARK: 底部

    private lazy var footerIcon = NSImageView().then {
        $0.setContentHuggingPriority(.required, for: .horizontal)
    }

    private lazy var footerLabel = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.lineBreakMode = .byTruncatingTail
        $0.font = .systemFont(ofSize: 11)
    }

    private lazy var footerView = NSStackView(views: [footerIcon, footerLabel]).then {
        $0.orientation = .horizontal
        $0.spacing = 5
        $0.alignment = .centerY
    }

    /// 按住 ⌘ 时显示的快速粘贴编号
    private lazy var shortcutBadge = CardBadge(style: .accent).then {
        $0.isHidden = true
    }
}

// MARK: - 系统方法

extension PasteCollectionViewItem {
    override func loadView() {
        view = HoverTrackingView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
    }

    override var isSelected: Bool {
        didSet { ringView.isHidden = !isSelected }
    }

    /// 面板高度变化时按卡片高度等比缩放头部(高度、图标、字号),
    /// 避免拖得很高时头部显得又矮又小。
    func updateLayout(cardHeight: CGFloat) {
        headerHeightConstraint?.constant = Layout.itemHeaderHeight(for: cardHeight)
        let iconSide = Layout.scaled(18, for: cardHeight, in: 16...24)
        appIconSizeConstraints.forEach { $0.constant = iconSide }
        appNameLabel.font = .systemFont(ofSize: Layout.scaled(12, for: cardHeight, in: 11...14), weight: .semibold)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: Layout.scaled(11, for: cardHeight, in: 10...13), weight: .regular)

        footerLabel.font = .systemFont(ofSize: Layout.scaled(11, for: cardHeight, in: 10...13))
    }

    /// 快速粘贴编号(1–9),nil 隐藏
    func setShortcutNumber(_ number: Int?) {
        if let number {
            shortcutBadge.text = "⌘\(number)"
            shortcutBadge.isHidden = false
        } else {
            shortcutBadge.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // ⌘+单击链接卡片:在浏览器中打开
        if event.type == .leftMouseDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           pModel?.type == .link {
            openLinkClick()
            return
        }
        if event.type == .leftMouseDown, event.clickCount == 2 {
            pasteAction()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pModel = nil
        surface = .standard
        imageFillView.image = nil
        contentLabel.attributedStringValue = NSAttributedString()
        appIconView.image = nil
        headerView.fillColor = .clear
        cardView.fillColor = AppColor.cardBackground
        pinMark.isHidden = true
        setShortcutNumber(nil)
        setHovering(false)
    }
}

// MARK: - UI布局

extension PasteCollectionViewItem {
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        applyShadow(hovering: false)
        (view as? HoverTrackingView)?.onHoverChange = { [weak self] in self?.setHovering($0) }
        (view as? HoverTrackingView)?.onMouseMove = { [weak self] in self?.applyLinkCursor() }

        view.addSubview(ringView)
        view.addSubview(cardView)
        cardView.addSubview(imageFillView)
        cardView.addSubview(contentLabel)
        cardView.addSubview(linkBox)
        cardView.addSubview(colorStack)
        cardView.addSubview(headerGradient)
        cardView.addSubview(headerView)
        cardView.addSubview(footerView)
        cardView.addSubview(imageBadgeStack)
        cardView.addSubview(shortcutBadge)

        cardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(Layout.itemShadowMargin)
            cardTopConstraint = make.top.equalToSuperview().offset(Layout.itemShadowMargin).constraint.layoutConstraints.first
            cardBottomConstraint = make.bottom.equalToSuperview().offset(-Layout.itemShadowMargin).constraint.layoutConstraints.first
        }
        ringView.snp.makeConstraints { make in
            make.edges.equalTo(cardView).inset(-Layout.itemRingGap)
        }

        initHeader()
        initContent()

        footerView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.itemInset)
            make.trailing.lessThanOrEqualTo(shortcutBadge.snp.leading).offset(-6)
            make.bottom.equalToSuperview().offset(-9)
            make.height.equalTo(16)
        }
        shortcutBadge.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.bottom.equalToSuperview().offset(-8)
        }
    }

    private func initHeader() {
        headerView.addSubview(appIconView)
        headerView.addSubview(appNameLabel)
        headerView.addSubview(pinMark)
        headerView.addSubview(timeLabel)
        headerView.addSubview(actionStack)

        headerView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            headerHeightConstraint = make.height.equalTo(Layout.itemHeaderHeight).constraint.layoutConstraints.first
        }
        headerGradient.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(56)
        }
        appIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.itemInset)
            make.centerY.equalToSuperview()
            appIconSizeConstraints = make.width.height.equalTo(18).constraint.layoutConstraints
        }
        appNameLabel.snp.makeConstraints { make in
            make.leading.equalTo(appIconView.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
        }
        pinMark.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(appNameLabel.snp.trailing).offset(4)
            make.centerY.equalToSuperview()
            make.size.equalTo(CardIcon.pinFilled.image.size)
        }
        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(pinMark.snp.trailing).offset(4)
            make.trailing.equalToSuperview().offset(-Layout.itemInset)
            make.centerY.equalToSuperview()
        }
        actionStack.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
        }
    }

    private func initContent() {
        contentLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.itemInset)
            make.trailing.equalToSuperview().offset(-Layout.itemInset)
            make.top.equalTo(headerView.snp.bottom).offset(4)
            make.bottom.equalTo(footerView.snp.top).offset(-6)
        }

        imageFillView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        imageBadgeStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().offset(-10)
        }

        colorStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.itemInset)
            make.trailing.equalToSuperview().offset(-Layout.itemInset)
            make.bottom.equalTo(footerView.snp.top).offset(-12)
        }

        linkBox.addSubview(linkIcon)
        linkIcon.addSubview(linkIconLabel)
        linkBox.addSubview(linkHostLabel)
        linkBox.addSubview(linkURLLabel)
        linkBox.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.itemInset)
            make.trailing.equalToSuperview().offset(-Layout.itemInset)
            make.top.equalTo(headerView.snp.bottom).offset(6)
            make.bottom.lessThanOrEqualTo(footerView.snp.top).offset(-8)
        }
        linkIcon.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().offset(12)
            make.width.height.equalTo(28)
        }
        linkIconLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview()
        }
        linkHostLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalTo(linkIcon.snp.bottom).offset(10)
        }
        linkURLLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(linkHostLabel)
            make.top.equalTo(linkHostLabel.snp.bottom).offset(2)
            make.bottom.equalToSuperview().offset(-12)
        }
    }

    /// 当前处于悬停态的卡片。快速移动或滚动时 mouseExited 可能丢失,
    /// 这里保证同一时刻只有一张卡片是悬停态。
    private static weak var hoveredItem: PasteCollectionViewItem?

    /// 面板隐藏时调用,清掉残留的悬停态
    static func clearHover() {
        hoveredItem?.setHovering(false)
    }

    /// 按下/松开 ⌘ 时刷新悬停卡片的指针(链接卡片 ⌘+单击可打开)
    static func refreshLinkCursor() {
        hoveredItem?.applyLinkCursor()
    }

    private func applyLinkCursor() {
        let commandOnly = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if isHovering, commandOnly, pModel?.type == .link {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func setHovering(_ hovering: Bool) {
        if hovering, let other = Self.hoveredItem, other !== self {
            other.setHovering(false)
        }
        if hovering {
            Self.hoveredItem = self
        } else if Self.hoveredItem === self {
            Self.hoveredItem = nil
        }
        guard hovering != isHovering else { return }
        isHovering = hovering
        applyLinkCursor()
        actionStack.isHidden = !hovering
        timeLabel.isHidden = hovering
        pinMark.isHidden = hovering || !(pModel?.isPinned ?? false)
        let pinned = pModel?.isPinned ?? false
        pinButton.setIcon(pinned ? .pinFilled : .pin,
                          toolTip: pinned ? String(localized: "Unpin") : String(localized: "Pin"))
        applyShadow(hovering: hovering)
        // 悬停时卡片轻微上浮(选中外圈跟随卡片一起移动)
        let lift = hovering ? Layout.itemHoverLift : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            cardTopConstraint?.animator().constant = Layout.itemShadowMargin - lift
            cardBottomConstraint?.animator().constant = -Layout.itemShadowMargin - lift
            view.layoutSubtreeIfNeeded()
        }
    }

    private func applyShadow(hovering: Bool) {
        view.shadow = NSShadow().then {
            $0.shadowColor = AppColor.cardShadow(hovering: hovering)
            $0.shadowBlurRadius = hovering ? 7 : 4
            $0.shadowOffset = NSSize(width: 0, height: hovering ? -2.5 : -1)
        }
    }
}

// MARK: - 数据更新

extension PasteCollectionViewItem {
    func pasteItem() {
        pasteAction()
    }

    func updateItem(model: PasteboardModel) {
        pModel = model
        [contentLabel, linkBox, colorStack, imageFillView, imageBadgeStack, headerGradient].forEach { $0.isHidden = true }

        switch model.type {
        case .image:
            setImageItem()
        case .color:
            setColorItem()
        default:
            setStringItem()
        }

        appNameLabel.stringValue = model.appName.isEmpty ? model.type.string : model.appName
        timeLabel.stringValue = model.date.timeAgo
        pinMark.isHidden = isHovering || !model.isPinned
        footerIcon.image = NSImage(systemSymbolName: Self.symbolName(for: model), accessibilityDescription: model.type.string)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        footerLabel.stringValue = model.type == .color ? model.type.string : model.sizeString(or: imageFillView.image)

        applyChromeColors()
        updateFooterVisibility()

        if !model.appPath.isEmpty {
            appIconView.image = NSWorkspace.shared.icon(forFile: model.appPath)
            if let cached = PasteDataStore.main.cachedColor(for: model) {
                applyAppTint(cached)
            } else {
                let hash = model.hashValue
                Task { [weak self] in
                    let color = await PasteDataStore.main.extractColor(from: model)
                    guard let self, self.pModel?.hashValue == hash else { return }
                    self.applyAppTint(color)
                }
            }
        } else {
            appIconView.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        }
        setViewMenu()
    }

    /// 只刷新置顶相关状态,不重配整张卡片(避免置顶切换时内容和头部颜色闪烁)
    func updatePinState(model: PasteboardModel) {
        pModel = model
        pinMark.isHidden = isHovering || !model.isPinned
        pinButton.setIcon(model.isPinned ? .pinFilled : .pin,
                          toolTip: model.isPinned ? String(localized: "Unpin") : String(localized: "Pin"))
        setViewMenu()
    }

    /// 图片卡的信息在胶囊里,不显示底部信息行
    private func updateFooterVisibility() {
        footerView.isHidden = pModel?.type == .image
    }

    /// 头部只叠一层很淡的来源 App 主色
    private func applyAppTint(_ color: NSColor?) {
        guard case .standard = surface, let color else {
            headerView.fillColor = .clear
            return
        }
        headerView.fillColor = AppColor.headerTint(color)
    }

    /// 头部/底部文字颜色随卡片底色自适应
    private func applyChromeColors() {
        let primary: NSColor
        let secondary: NSColor
        switch surface {
        case .standard:
            primary = .labelColor
            secondary = .secondaryLabelColor
        case .custom(let bg):
            let base = HexColorValidator.textColor(for: bg)
            primary = base.withAlphaComponent(0.9)
            secondary = base.withAlphaComponent(0.65)
        case .image:
            primary = AppColor.onImagePrimary
            secondary = AppColor.onImageSecondary
        }
        appNameLabel.textColor = primary
        timeLabel.textColor = secondary
        footerLabel.textColor = secondary
        footerIcon.contentTintColor = secondary
        [pinButton, deleteButton].forEach {
            $0.contentTintColor = primary
            $0.onDarkSurface = (primary.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.6 && !Self.isStandard(surface)
        }
    }

    private static func isStandard(_ surface: Surface) -> Bool {
        if case .standard = surface { return true }
        return false
    }

    private static func symbolName(for model: PasteboardModel) -> String {
        switch model.type {
        case .image: return "photo"
        case .color: return "paintpalette"
        default:
            if model.pasteboardType != .string { return "textformat" }
            if model.type == .link { return "link" }
            if looksLikeCode(model.dataString) { return "chevron.left.forwardslash.chevron.right" }
            return "text.alignleft"
        }
    }

    private func setStringItem() {
        guard let model = pModel, let att = model.attributeString else { return }
        let showAtt = att.length > maxLength ? att.attributedSubstring(from: NSMakeRange(0, maxLength)) : att

        // 富文本自带底色:保留原样展示
        if att.length > 0, let color = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor {
            surface = .custom(color)
            cardView.fillColor = color
            contentLabel.attributedStringValue = showAtt
            contentLabel.isHidden = false
            return
        }

        surface = .standard
        cardView.fillColor = AppColor.cardBackground

        if let url = PasteboardModel.linkURL(in: model.dataString) {
            let host = (url.host ?? "").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            linkIconLabel.stringValue = host.first.map { String($0).uppercased() } ?? "🔗"
            linkHostLabel.stringValue = host
            linkHostLabel.font = .systemFont(ofSize: host.count > 16 ? 13 : 15, weight: .semibold)
            var rest = url.absoluteString
            if let range = rest.range(of: host) { rest = String(rest[range.upperBound...]) }
            linkURLLabel.stringValue = rest.isEmpty ? url.absoluteString : String(rest.prefix(maxLength))
            linkBox.isHidden = false
            return
        }

        let text = showAtt.string
        let styled: NSAttributedString
        if Self.looksLikeCode(text) {
            styled = Self.highlightedCode(text)
        } else if Self.isShortText(text) {
            styled = Self.styled(text.trimmingCharacters(in: .whitespacesAndNewlines),
                                 font: .systemFont(ofSize: 22, weight: .semibold), lineSpacing: 2)
        } else {
            styled = Self.styled(text, font: .systemFont(ofSize: 13), lineSpacing: 3)
        }
        contentLabel.attributedStringValue = styled
        contentLabel.isHidden = false
    }

    private func setImageItem() {
        surface = .image
        cardView.fillColor = .quaternaryLabelColor
        imageFillView.isHidden = false
        headerGradient.isHidden = false
        if let data = pModel?.data, let image = NSImage(data: data) {
            imageFillView.image = image
        }
        let size = pModel?.sizeString(or: imageFillView.image) ?? ""
        imageSizeBadge.text = size
        imageSizeBadge.isHidden = size.isEmpty
        let hasText = !(pModel?.ocrText?.isEmpty ?? true)
        ocrBadge.text = "Aa"
        ocrBadge.toolTip = String(localized: "Text Detected")
        ocrBadge.isHidden = !hasText
        imageBadgeStack.isHidden = size.isEmpty && !hasText
    }

    private func setColorItem() {
        guard let hexColor = NSColor(pModel?.hexColorString ?? "") else {
            setStringItem()
            return
        }
        surface = .custom(hexColor)
        cardView.fillColor = hexColor
        let textColor = HexColorValidator.textColor(for: hexColor)

        hexLabel.stringValue = (pModel?.hexColorString ?? "").uppercased()
        hexLabel.textColor = textColor
        if let rgb = hexColor.usingColorSpace(.sRGB) {
            rgbLabel.stringValue = String(format: "RGB  %d  %d  %d",
                                          Int(round(rgb.redComponent * 255)),
                                          Int(round(rgb.greenComponent * 255)),
                                          Int(round(rgb.blueComponent * 255)))
        } else {
            rgbLabel.stringValue = ""
        }
        rgbLabel.textColor = textColor.withAlphaComponent(0.7)

        for (view, step) in zip(swatchViews, Self.swatchSteps) {
            let color: NSColor
            if step < 0 {
                color = hexColor.blended(withFraction: -step, of: .white) ?? hexColor
            } else if step > 0 {
                color = hexColor.blended(withFraction: step, of: .black) ?? hexColor
            } else {
                color = hexColor
            }
            view.fillColor = color
            view.borderWidth = step == 0 ? 1.5 : 0
            view.borderColor = textColor.withAlphaComponent(0.9)
        }
        colorStack.isHidden = false
    }
}

// MARK: - 文本排版

extension PasteCollectionViewItem {
    private static func styled(_ text: String, font: NSFont, lineSpacing: CGFloat,
                               color: NSColor = .labelColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    /// 粗略判断是否为代码/命令:多行且符号密度较高,或以 shell 提示符开头
    private static func looksLikeCode(_ text: String) -> Bool {
        let sample = text.prefix(maxLength)
        let trimmed = sample.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("% ") { return true }
        guard sample.contains("\n") else { return false }
        // 中文为主的文本(日志、聊天记录)即使符号多也不算代码
        let asciiCount = sample.unicodeScalars.filter(\.isASCII).count
        guard Double(asciiCount) / Double(max(sample.unicodeScalars.count, 1)) > 0.9 else { return false }
        let symbols = sample.filter { "{}[]();=<>".contains($0) }.count
        return Double(symbols) / Double(max(sample.count, 1)) > 0.05
    }

    /// 短文本(单行、≤ 24 字)放大显示
    private static func isShortText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 24 && !trimmed.contains("\n")
    }

    private static let keywordRegex = try? NSRegularExpression(
        pattern: "\\b(func|let|var|if|else|for|while|return|switch|case|default|class|struct|enum|protocol|extension|import|guard|const|function|def|public|private|static|self|true|false|nil|null|new|in|async|await|try)\\b"
    )
    private static let stringRegex = try? NSRegularExpression(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'")

    /// 等宽字体 + 关键字/字符串着色
    private static func highlightedCode(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.lineBreakMode = .byClipping
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        let range = NSRange(location: 0, length: result.length)
        keywordRegex?.matches(in: text, range: range).forEach {
            result.addAttribute(.foregroundColor, value: AppColor.codeKeyword, range: $0.range)
        }
        stringRegex?.matches(in: text, range: range).forEach {
            result.addAttribute(.foregroundColor, value: AppColor.codeString, range: $0.range)
        }
        return result
    }

    private func setViewMenu() {
        // 只挂一个空菜单并设 delegate;菜单项在每次右键弹出时由 menuNeedsUpdate 现构建,
        // 保证 frontAppName、纯文本开关等运行时状态始终读到最新值(cell 复用后不会用旧菜单)。
        let menu = NSMenu()
        menu.delegate = self
        view.menu = menu
    }

    /// 每次右键弹出前重建菜单项,读取当时的前台应用名与纯文本开关。
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if let name = AppContext.coordinator.frontAppName {
            let item = NSMenuItem(title: String(localized: "Paste to \(name)"), action: #selector(pasteOriginalTextClick), keyEquivalent: "")
            menu.addItem(item)
        }
        // "始终以纯文本粘贴"开启时,默认粘贴已是纯文本,该菜单项冗余,隐藏之。
        if pModel?.type == .string || pModel?.type == .link, !PasteUserDefaults.pasteOnlyText {
            let item1 = NSMenuItem(title: String(localized: "Paste as Plain Text"), action: #selector(pasteTextClick), keyEquivalent: "")
            menu.addItem(item1)
        }

        if pModel?.type == .color {
            let itemColor = NSMenuItem(title: String(localized: "Paste as #RRGGBB"), action: #selector(pasteTextClick), keyEquivalent: "")
            menu.addItem(itemColor)
        }

        // 图片:直接取用 OCR 文字(未识别则点击时当场识别)
        if pModel?.type == .image {
            if let name = AppContext.coordinator.frontAppName {
                let pasteTextItem = NSMenuItem(title: String(localized: "Paste Text to \(name)"), action: #selector(pasteOCRTextClick), keyEquivalent: "")
                menu.addItem(pasteTextItem)
            }
            let copyTextItem = NSMenuItem(title: String(localized: "Copy Text"), action: #selector(copyOCRTextClick), keyEquivalent: "")
            menu.addItem(copyTextItem)
        }

        if pModel?.type == .link {
            menu.addItem(NSMenuItem(title: String(localized: "Open in Browser (⌘+Click)"), action: #selector(openLinkClick), keyEquivalent: ""))
        }

        let previewItem = NSMenuItem(title: String(localized: "Preview"), action: #selector(previewItemAction), keyEquivalent: " ")
        previewItem.keyEquivalentModifierMask = .init(rawValue: 0)
        menu.addItem(previewItem)
        menu.addItem(.separator())
        let pinTitle = (pModel?.isPinned ?? false) ? String(localized: "Unpin") : String(localized: "Pin")
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinClick), keyEquivalent: "")
        menu.addItem(pinItem)
        let item2 = NSMenuItem(title: String(localized: "Copy"), action: #selector(copyItemData), keyEquivalent: "")
        menu.addItem(item2)
        let item3 = NSMenuItem(title: String(localized: "Delete"), action: #selector(deleteItem), keyEquivalent: "d")
        item3.keyEquivalentModifierMask = .init(rawValue: 0)
        menu.addItem(item3)
    }
}

// MARK: - NSMenuDelegate

extension PasteCollectionViewItem: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }
}

// MARK: - 事件处理

extension PasteCollectionViewItem {
    @objc
    private func pasteTextClick() {
        pasteAction(false)
    }

    @objc
    private func pasteOriginalTextClick() {
        pasteAction(true)
    }

    private func pasteAction(_ isOriginal: Bool = true) {
        guard let pModel else { return }
        delegate?.pasteItem(pModel, isOriginal: isOriginal)
    }

    @objc
    private func copyItemData() {
        guard let pModel else { return }
        delegate?.copyItem(pModel)
    }

    @objc
    private func copyOCRTextClick() {
        guard let pModel else { return }
        delegate?.copyOCRText(pModel)
    }

    @objc
    private func pasteOCRTextClick() {
        guard let pModel else { return }
        delegate?.pasteOCRText(pModel)
    }

    @objc
    private func deleteItem() {
        if let pModel, let indexPath = collectionView?.indexPath(for: self) {
            delegate?.deleteItem(pModel, indexPath: indexPath)
        }
    }

    @objc
    private func openLinkClick() {
        guard let pModel, let url = PasteboardModel.linkURL(in: pModel.dataString) else { return }
        AppContext.coordinator.dismissWindow {
            NSWorkspace.shared.open(url)
        }
    }

    @objc
    private func previewItemAction() {
        guard let pModel else { return }
        delegate?.previewItem(pModel, relativeTo: view)
    }

    @objc
    private func togglePinClick() {
        guard let pModel else { return }
        delegate?.togglePin(pModel)
    }
}

extension PasteCollectionViewItem: UserInterfaceItemIdentifier {}
