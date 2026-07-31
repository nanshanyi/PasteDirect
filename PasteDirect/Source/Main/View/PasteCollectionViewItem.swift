//
//  PasteCollectionViewItem.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit
import Carbon
import Combine
import SnapKit
import Foundation

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

final class PasteCollectionViewItem: NSCollectionViewItem {
    weak var delegate: PasteCollectionViewItemDelegate?
    private var pModel: PasteboardModel?
    private var isAttribute: Bool = true
    private var appearanceCancellable: AnyCancellable?
    private var topViewHeightConstraint: NSLayoutConstraint?
    private var pinBadgeSizeConstraints: [NSLayoutConstraint] = []
    private(set) var isCompact: Bool = false

    // compact 模式约束
    private var compactConstraints: [NSLayoutConstraint] = []
    // normal 模式约束
    private var normalConstraints: [NSLayoutConstraint] = []

    private lazy var contentView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.masksToBounds = true
        $0.layer?.backgroundColor = .clear
        $0.layer?.cornerRadius = Layout.itemCornerRadius
        $0.layer?.borderColor = NSColor("#3970ff")?.cgColor
    }

    private lazy var topView = NSView().then {
        $0.wantsLayer = true
    }
    
    private lazy var topMask = NSView().then {
        $0.wantsLayer = true
        $0.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
    }

    private lazy var iconImageView = NSImageView().then {
        $0.alignment = .center
        $0.imageScaling = .scaleAxesIndependently
    }

    /// 置顶标记:卡片右上角的圆形徽章(琥珀橙圆底 + 白色图钉),仅置顶项显示。
    /// 此为基准尺寸(@ item 260),实际尺寸由 updateLayout 按面板高度动态覆盖。
    private static let pinBadgeSize: CGFloat = 26
    /// 徽章底色:琥珀橙,置顶/收藏类标记的经典色,不与系统主题色/头部动态底色撞色
    private static let pinBadgeColor = NSColor("#FF9500") ?? .systemOrange

    private lazy var pinBadge = NSView().then {
        $0.wantsLayer = true
        $0.layer?.backgroundColor = Self.pinBadgeColor.cgColor
        $0.layer?.cornerRadius = Self.pinBadgeSize / 2
        $0.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        $0.layer?.borderWidth = 1.5
        // 轻微投影,让徽章从彩色头部上浮起来
        $0.shadow = NSShadow().then { s in
            s.shadowColor = NSColor.black.withAlphaComponent(0.35)
            s.shadowBlurRadius = 3
            s.shadowOffset = NSSize(width: 0, height: -1)
        }
        $0.isHidden = true
        $0.addSubview(pinImageView)
        pinImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private lazy var pinImageView = NSImageView().then {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        $0.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        $0.contentTintColor = .white
        $0.alignment = .center
    }

    private lazy var typeLabel = NSlabel().then {
        $0.textColor = .white
        $0.maximumNumberOfLines = 1
        $0.backgroundColor = .clear
        $0.font = .systemFont(ofSize: 18, weight: .medium)
    }

    private lazy var timeLabel = NSlabel().then {
        $0.textColor = .white
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .systemFont(ofSize: 12)
    }

    private lazy var contentLabel = NSlabel().then {
        $0.textColor = .textColor
        $0.backgroundColor = .clear
        $0.font = .systemFont(ofSize: 14)
        $0.lineBreakMode = .byCharWrapping
    }

    private lazy var pasteImageView = NSImageView().then {
        $0.alignment = .center
    }

    private lazy var imageContentView = PasteEffectImageView().then {
        $0.addSubview(pasteImageView)
        pasteImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.spacing)
            make.trailing.equalToSuperview().offset(-Layout.spacing)
            make.top.equalToSuperview().offset(Layout.spacing)
            make.bottom.equalToSuperview().offset(-Layout.itemBottomOffset)
        }
    }

    private lazy var bottomView = NSView().then {
        $0.wantsLayer = true
        $0.addSubview(bottomLabel)
        bottomLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }

    private lazy var bottomLabel = NSlabel().then {
        $0.alignment = .center
        $0.textColor = .systemGray
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .systemFont(ofSize: 12)
    }
}

// MARK: - 系统方法

extension PasteCollectionViewItem {
    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        initObserver()
    }

    override var isSelected: Bool {
        didSet {
            contentView.layer?.borderWidth = isSelected ? Layout.itemBorderWidth : 0
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // bounds 是 cell 高(含上下阴影留白),扣除后才是卡片高度
        let cardHeight = view.bounds.height - Layout.itemShadowMargin * 2
        let topHeight = isCompact ? 36.0 : Layout.dynamicTopViewHeight(for: cardHeight)
        topViewHeightConstraint?.constant = topHeight
    }

    func updateLayout(compact: Bool, itemHeight: CGFloat) {
        if compact != isCompact {
            isCompact = compact
            applyLayoutMode(compact: compact, itemHeight: itemHeight)
        } else if !compact {
            typeLabel.font = .systemFont(ofSize: Layout.dynamicTypeFontSize(for: itemHeight), weight: .medium)
        }
        updatePinBadgeSize(for: itemHeight)
    }

    /// 徽章尺寸随 item 高度缩放,避免小面板时过大
    private func updatePinBadgeSize(for itemHeight: CGFloat) {
        let size = Layout.dynamicPinBadgeSize(for: itemHeight)
        pinBadgeSizeConstraints.forEach { $0.constant = size }
        pinBadge.layer?.cornerRadius = size / 2
        let symbolSize = size * 13 / 26
        let base = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .bold))
        // 直接旋转图片本身(顺时针 45°),不依赖 layer/frame 变换,规避布局重置
        pinImageView.image = base?.rotated(byDegrees: -45)
    }

    private func applyLayoutMode(compact: Bool, itemHeight: CGFloat) {
        if compact {
            NSLayoutConstraint.deactivate(normalConstraints)
            NSLayoutConstraint.activate(compactConstraints)
            typeLabel.font = .systemFont(ofSize: 14, weight: .medium)
            timeLabel.font = .systemFont(ofSize: 11)
        } else {
            NSLayoutConstraint.deactivate(compactConstraints)
            NSLayoutConstraint.activate(normalConstraints)
            typeLabel.font = .systemFont(ofSize: Layout.dynamicTypeFontSize(for: itemHeight), weight: .medium)
            timeLabel.font = .systemFont(ofSize: 12)
        }

        let topHeight = compact ? 36.0 : Layout.dynamicTopViewHeight(for: itemHeight)
        topViewHeightConstraint?.constant = topHeight
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.type == .leftMouseDown, event.clickCount == 2 {
            pasteAction()
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        pModel = nil
        pasteImageView.image = nil
        imageContentView.image = nil
        contentLabel.stringValue = ""
        contentLabel.attributedStringValue = NSAttributedString()
        contentLabel.alignment = .left
        contentView.layer?.backgroundColor = .clear
        topView.layer?.backgroundColor = NSColor.bg.cgColor
        iconImageView.image = nil
        pinBadge.isHidden = true
        isAttribute = true
    }
}

// MARK: - UI布局

extension PasteCollectionViewItem {
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.shadow = NSShadow().then {
            $0.shadowBlurRadius = 3
        }
        initTopView()
        initContentView()
    }

    private func initTopView() {
        topView.addSubview(topMask)
        topView.addSubview(typeLabel)
        topView.addSubview(timeLabel)
        topView.addSubview(iconImageView)

        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        topMask.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.bottom.trailing.equalToSuperview().offset(-4)
            make.width.equalTo(iconImageView.snp.height)
        }

        // normal 模式约束（两行，icon 贴底）
        normalConstraints = [
            typeLabel.leadingAnchor.constraint(equalTo: topView.leadingAnchor, constant: Layout.spacing),
            typeLabel.bottomAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: typeLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: iconImageView.centerYAnchor, constant: 4),
        ]

        // compact 模式约束（单行，icon 小）
        compactConstraints = [
            typeLabel.leadingAnchor.constraint(equalTo: topView.leadingAnchor, constant: Layout.spacing),
            typeLabel.centerYAnchor.constraint(equalTo: topView.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 2),
            timeLabel.centerYAnchor.constraint(equalTo: topView.centerYAnchor),
        ]

        NSLayoutConstraint.activate(normalConstraints)
    }

    private func initContentView() {
        view.addSubview(contentView)
        contentView.addSubview(topView)
        contentView.addSubview(imageContentView)
        contentView.addSubview(contentLabel)
        contentView.addSubview(bottomView)
        // 徽章挂到最外层 view(非裁剪),才能浮出卡片圆角边缘并投影
        view.addSubview(pinBadge)

        contentView.snp.makeConstraints { make in
            // 只上下留 margin,让阴影落在 cell 内不被垂直裁切;左右贴边,横向间距由 lineSpacing 控制
            make.leading.trailing.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(Layout.itemShadowMargin)
        }

        pinBadge.snp.makeConstraints { make in
            // 顶到卡片右上角,避免越过边界被上层 scrollView 裁切
            make.top.equalTo(contentView)
            make.trailing.equalTo(contentView)
            self.pinBadgeSizeConstraints = make.width.height.equalTo(Self.pinBadgeSize).constraint.layoutConstraints
        }

        topView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            self.topViewHeightConstraint = make.height.equalTo(Layout.itemTopViewHeight).constraint.layoutConstraints.first
        }

        imageContentView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(topView.snp.bottom)
        }

        contentLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.spacing)
            make.trailing.equalToSuperview().offset(-Layout.spacing)
            make.top.equalTo(topView.snp.bottom).offset(Layout.spacing)
            make.bottom.equalToSuperview().offset(-Layout.itemBottomOffset)
        }

        bottomView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(Layout.itemBottomViewHeight)
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
        switch model.type {
        case .image:
            setImageItem()
        case .string:
            setStringItem()
        case .color:
            setColorItem()
        default:
            break
        }
        if !model.appPath.isEmpty {
            iconImageView.image = NSWorkspace.shared.icon(forFile: model.appPath)
            Task {
                let color = await PasteDataStore.main.extractColor(from: model)
                updateTopColor(color)
            }
        } else {
            updateTopColor(.bg)
        }
        setViewMenu()
        pinBadge.isHidden = !model.isPinned
        timeLabel.stringValue = model.date.timeAgo
        typeLabel.stringValue = model.type.string
        bottomLabel.stringValue = model.sizeString(or: pasteImageView.image)
        if model.pasteboardType.isText(), let bgColor = NSColor(cgColor: contentView.layer?.backgroundColor ?? .black) {
            let textColor = HexColorValidator.textColor(for: bgColor)
            bottomLabel.textColor = textColor.withAlphaComponent(0.6)
        } else {
            bottomLabel.textColor = .systemGray
        }
    }
    
    @MainActor
    private func updateTopColor(_ color: NSColor?) {
        topView.layer?.backgroundColor = color?.cgColor ?? NSColor.bg.cgColor
    }

    private func setStringItem() {
        imageContentView.isHidden = true
        contentLabel.isHidden = false
        guard let att = pModel?.attributeString else { return }
        let showAtt = att.length > maxLength ? att.attributedSubstring(from: NSMakeRange(0, maxLength)) : att
        if att.length > 0,
           let color = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor {
            contentLabel.attributedStringValue = showAtt
            contentView.layer?.backgroundColor = color.cgColor
            isAttribute = true
        } else {
            isAttribute = false
            contentLabel.stringValue = showAtt.string
            contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }

    private func setImageItem() {
        imageContentView.isHidden = false
        contentLabel.isHidden = true
        if let data = pModel?.data, let image = NSImage(data: data) {
            pasteImageView.image = image
            imageContentView.image = image
        }
    }

    private func setColorItem() {
        imageContentView.isHidden = true
        contentLabel.isHidden = false
        guard let hexColor = NSColor(pModel?.hexColorString ?? "") else {
            // 降级为普通文本显示
            setStringItem()
            return
        }
        
        // 设置背景色为颜色值
        contentView.layer?.backgroundColor = hexColor.cgColor
        // 计算合适的文本颜色
        let textColor = HexColorValidator.textColor(for: hexColor)
        
        // 创建富文本：显示原始文本
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: textColor
        ]
        let attributedText = NSAttributedString(string: pModel?.dataString ?? "", attributes: attrs)
        contentLabel.attributedStringValue = attributedText
        contentLabel.alignment = .center
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
        if pModel?.type == .string, !PasteUserDefaults.pasteOnlyText {
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
    private func initObserver() {
        appearanceCancellable = NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in
                appearance.performAsCurrentDrawingAppearance {
                    guard let self else { return }
                    // 徽章橙底+白描边随外观刷新(cgColor 不自动跟随)
                    self.pinBadge.layer?.backgroundColor = Self.pinBadgeColor.cgColor
                    self.pinBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
                    guard !self.isAttribute else { return }
                    self.contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
                }
            }
    }

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

private extension NSImage {
    /// 返回绕中心旋转指定角度(度,负为顺时针)的新图。
    /// 保持 isTemplate,使 contentTintColor 仍生效。
    func rotated(byDegrees degrees: CGFloat) -> NSImage {
        let radians = degrees * .pi / 180
        // 旋转后包围盒可能变大,用对角线边长的正方形画布容纳,避免裁切
        let side = ceil(hypot(size.width, size.height))
        let newSize = NSSize(width: side, height: side)
        let rotated = NSImage(size: newSize)
        rotated.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: side / 2, yBy: side / 2)
        transform.rotate(byRadians: radians)
        transform.concat()
        let drawRect = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        rotated.unlockFocus()
        rotated.isTemplate = isTemplate
        return rotated
    }
}

