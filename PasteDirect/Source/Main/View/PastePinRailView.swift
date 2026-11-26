//
//  PastePinRailView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/11/26.
//

import AppKit
import SnapKit

/// 置顶折叠条：固定在列表左侧的窄条，收起时置顶项只在这里显示数量和来源 App，
/// 让最近复制的条目始终从第一张卡开始。点击展开/收起，悬停弹出置顶清单。
/// 底色不在这里画：收起和展开都是同一块 PinnedGroupBackgroundView，只是宽窄不同。
final class PastePinRailView: NSView {
    static let width: CGFloat = 56
    /// 折叠条与第一张卡片之间的距离
    static let gap: CGFloat = 12
    private static let maxAppIcons = 4
    private static let appIconSize: CGFloat = 22

    var onClick: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private var isPressed = false

    private let pinView = NSImageView().then {
        $0.image = CardIcon.pinFilled.image
        $0.contentTintColor = AppColor.pinned
    }

    private let countLabel = NSlabel().then {
        $0.font = .systemFont(ofSize: 12, weight: .bold)
        $0.textColor = AppColor.pinned
        $0.alignment = .center
        $0.drawsBackground = false
    }

    private let appStack = NSStackView().then {
        $0.orientation = .vertical
        $0.alignment = .centerX
        // 图标上下叠压，像一摞卡片
        $0.spacing = -6
    }

    private let chevronView = NSImageView().then {
        $0.contentTintColor = .tertiaryLabelColor
        $0.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(pinView)
        addSubview(countLabel)
        addSubview(appStack)
        addSubview(chevronView)
        pinView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(14)
        }
        countLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(pinView.snp.bottom).offset(6)
        }
        chevronView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-12)
        }
        appStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(chevronView.snp.top).offset(-10)
            make.top.greaterThanOrEqualTo(countLabel.snp.bottom).offset(8)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(items: [PasteboardModel], expanded: Bool) {
        countLabel.stringValue = "\(items.count)"
        let symbol = expanded ? "chevron.left" : "chevron.right"
        chevronView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        toolTip = expanded ? String(localized: "Hide Pinned") : String(localized: "Show Pinned")
        // 展开后卡片就在旁边，图标堆只在收起时显示
        appStack.isHidden = expanded

        var seen = Set<String>()
        let paths = items.map(\.appPath).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.maxAppIcons)
        appStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for path in paths {
            let icon = NSImageView()
            icon.image = NSWorkspace.shared.icon(forFile: path)
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.snp.makeConstraints { make in make.width.height.equalTo(Self.appIconSize) }
            appStack.addArrangedSubview(icon)
        }
    }

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
