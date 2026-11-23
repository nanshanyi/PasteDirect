//
//  PasteFilterItem.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/09.
//

import AppKit

final class PasteFilterItem: NSCollectionViewItem, UserInterfaceItemIdentifier {

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hasIcon = false

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 6
        view = root

        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: 28),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        view.addGestureRecognizer(click)

        updateAppearance()
    }

    private var labelLeading: NSLayoutConstraint?
    private var labelTrailing: NSLayoutConstraint?

    func configure(title: String, icon: NSImage?, isOn: Bool) {
        label.stringValue = title
        hasIcon = icon != nil
        iconView.image = icon
        iconView.isHidden = !hasIcon

        labelLeading?.isActive = false
        let leading: CGFloat = hasIcon ? 28 : 10
        labelLeading = label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: leading)
        labelLeading?.isActive = true

        if labelTrailing == nil {
            labelTrailing = label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
            labelTrailing?.isActive = true
        }

        self.isSelected = isOn
        updateAppearance()
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    @objc private func tapped() {
        onClick?()
    }

    private func updateAppearance() {
        if isSelected {
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            label.textColor = .controlAccentColor
        } else {
            view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            label.textColor = .labelColor
        }
    }

    func fittingWidth() -> CGFloat {
        let textWidth = label.intrinsicContentSize.width
        return (hasIcon ? 28 : 10) + textWidth + 10
    }
}

// MARK: - PillSegmentedControl

/// 顶栏类型切换:浅灰槽 + 选中项白色胶囊(深色模式为浅灰胶囊),无分隔线
final class PillSegmentedControl: NSView {
    var onChange: ((Int) -> Void)?

    var selectedIndex: Int = 0 {
        didSet { updateSelection(animated: oldValue != selectedIndex) }
    }

    private var buttons: [NSButton] = []
    private let titles: [String]
    private var counts: [Int?]
    private let track = PillLayerView()
    private let pill = PillLayerView()
    private let stack = NSStackView()

    init(titles: [String]) {
        self.titles = titles
        self.counts = Array(repeating: nil, count: titles.count)
        super.init(frame: .zero)
        track.fill = { AppColor.toolbarFill }
        track.radius = 9
        pill.fill = { AppColor.segmentPill }
        pill.radius = 7
        pill.shadow = NSShadow().then {
            $0.shadowColor = AppColor.segmentPillShadow
            $0.shadowBlurRadius = 2
            $0.shadowOffset = NSSize(width: 0, height: -0.5)
        }
        addSubview(track)
        addSubview(pill)
        addSubview(stack)
        track.snp.makeConstraints { make in make.edges.equalToSuperview() }

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.snp.makeConstraints { make in make.edges.equalToSuperview().inset(2) }

        for (index, title) in titles.enumerated() {
            let button = PaddedButton(title: title, target: self, action: #selector(tapped(_:)))
            button.tag = index
            button.isBordered = false
            button.refusesFirstResponder = true
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.snp.makeConstraints { make in
                make.height.equalTo(22)
                make.width.greaterThanOrEqualTo(44)
            }
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        updateSelection(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTitles()
    }

    @objc private func tapped(_ sender: NSButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onChange?(sender.tag)
    }

    private func updateSelection(animated: Bool) {
        guard buttons.indices.contains(selectedIndex) else { return }
        layoutSubtreeIfNeeded()
        let target = buttons[selectedIndex].convert(buttons[selectedIndex].bounds, to: self)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                pill.animator().frame = target
            }
        } else {
            pill.frame = target
        }
        refreshTitles()
    }

    /// 设置每段的条数,nil 表示不显示(如「全部」)
    func setCounts(_ counts: [Int?]) {
        guard counts.count == titles.count, counts != self.counts else { return }
        self.counts = counts
        refreshTitles()
    }

    private static let countFormatter = NumberFormatter().then { $0.numberStyle = .decimal }

    private func refreshTitles() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            let title = NSMutableAttributedString(string: titles[index], attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: AppColor.segmentText(selected: selected, isCount: false),
            ])
            if let count = counts[index], count > 0 {
                let text = Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
                title.append(NSAttributedString(string: " " + text, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: AppColor.segmentText(selected: selected, isCount: true),
                    .baselineOffset: 0.5,
                ]))
            }
            button.attributedTitle = title
        }
        needsLayout = true
    }
}

/// 左右各留 10pt 内边距的无边框按钮,让选中胶囊不贴字
final class PaddedButton: NSButton {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 20, height: size.height)
    }
}

/// 顶栏图标按钮:平时只有图标,悬停时出现圆角浅灰底(与设计稿 .icon-btn 一致)
final class ToolbarIconButton: NSButton {
    private var isHovering = false { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?

    init(symbol: String, pointSize: CGFloat = 13, toolTip: String? = nil) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        refusesFirstResponder = true
        wantsLayer = true
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        contentTintColor = AppColor.toolbarIcon
        self.toolTip = toolTip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// NSButton 默认有上下对齐内边距,约束 28×28 时实际 frame 会被撑成 28×32,
    /// 悬停底色变成竖长方形。清零后 frame 与约束一致,保持正方形。
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = isHovering ? AppColor.toolbarFill.cgColor : NSColor.clear.cgColor
    }

    /// 只创建一次,随视图尺寸自动更新(.inVisibleRect)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func viewDidHide() {
        super.viewDidHide()
        isHovering = false
    }
}

/// 颜色在 updateLayer 中按当前外观解析的圆角块
final class PillLayerView: NSView {
    var fill: () -> NSColor = { .clear } { didSet { needsDisplay = true } }
    var radius: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill().cgColor
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
