//
//  PasteCardComponents.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit
import SnapKit

// MARK: - 卡片辅助视图

/// 以 NSColor 描述填充/描边的图层视图;颜色在 updateLayer 中解析,
/// 系统切换深浅色时自动重绘,无需手动监听外观。
final class CardLayerView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }
    var clipsContent = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = fillColor.cgColor
        layer.borderColor = borderColor.cgColor
        layer.borderWidth = borderWidth
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = clipsContent
    }
}

/// 悬停时出现在卡片头部的圆形快捷按钮。
/// 自绘而不用 NSButton:NSButton 的固有尺寸会和固定宽高约束打架,被拉成椭圆。
final class CardActionButton: NSView {
    static let size: CGFloat = 22

    weak var target: AnyObject?
    var action: Selector?

    /// 位于彩色/图片底上时用白色半透明底和白色图标
    var onDarkSurface = false { didSet { needsDisplay = true } }

    var contentTintColor: NSColor? {
        get { iconView.contentTintColor }
        set { iconView.contentTintColor = newValue }
    }

    private let iconView = NSImageView()
    private var isHighlighted = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(icon: CardIcon, toolTip: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        addSubview(iconView)
        iconView.snp.makeConstraints { make in make.center.equalToSuperview() }
        snp.makeConstraints { make in make.width.height.equalTo(Self.size) }
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setIcon(icon, toolTip: toolTip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.size, height: Self.size) }

    func setIcon(_ icon: CardIcon, toolTip: String) {
        iconView.image = icon.image
        self.toolTip = toolTip
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Self.size / 2
        layer.cornerCurve = .continuous
        layer.backgroundColor = AppColor.actionButtonFill(onDarkSurface: onDarkSurface,
                                                          highlighted: isHighlighted, pressed: isPressed).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false; isPressed = false }

    // 吞掉按下事件,避免触发 cell 的选中/拖拽
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        defer { isPressed = false }
        guard isPressed, bounds.contains(convert(event.locationInWindow, from: nil)), let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 卡片上的小图标,全部来自 SF Symbols。
/// 图钉顺时针旋转 45° 斜放(与设计稿一致);pin.slash 旋转后斜线会变成竖线,
/// 所以「已置顶」用实心图钉表示,按钮本身即是状态。
enum CardIcon {
    case pin, pinFilled, trash

    private static let pointSize: CGFloat = 11

    private var spec: (name: String, weight: NSFont.Weight, degrees: CGFloat) {
        switch self {
        case .pin: return ("pin", .regular, -45)
        case .pinFilled: return ("pin.fill", .regular, -45)
        case .trash: return ("trash", .light, 0)
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// 模板图,颜色由 contentTintColor 决定;画布为旋转后的包围盒,不裁切
    @MainActor
    var image: NSImage {
        let spec = spec
        if let cached = Self.cache[spec.name] { return cached }
        guard let base = NSImage(systemSymbolName: spec.name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: Self.pointSize, weight: spec.weight))
        else { return NSImage() }
        let radians = spec.degrees * .pi / 180
        let w = base.size.width, h = base.size.height
        let canvas = NSSize(width: ceil(abs(w * cos(radians)) + abs(h * sin(radians))),
                            height: ceil(abs(w * sin(radians)) + abs(h * cos(radians))))
        let image = NSImage(size: canvas, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byRadians: radians)
            transform.concat()
            base.draw(in: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
            return true
        }
        image.isTemplate = true
        Self.cache[spec.name] = image
        return image
    }
}

/// 跟踪鼠标进出的 cell 根视图
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var onMouseMove: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
    override func mouseMoved(with event: NSEvent) { onMouseMove?() }
}

/// 自上而下由半透明黑渐隐的遮罩,用于图片卡头部
final class GradientView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [AppColor.imageHeaderGradient.top.cgColor, AppColor.imageHeaderGradient.bottom.cgColor]
        // layer 坐标 y 轴向上:从顶部(1)渐变到底部(0)
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 等比填满(居中裁切)的图片视图
final class AspectFillImageView: NSView {
    var image: NSImage? {
        didSet { layer?.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 卡片上的小胶囊标签(图片尺寸 / 识别文字 / ⌘ 编号)
final class CardBadge: NSView {
    enum Style { case dark, light, accent }

    private let style: Style
    private let label = NSlabel().then {
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(label)
        label.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview().offset(7)
            make.trailing.equalToSuperview().offset(-7)
        }
        snp.makeConstraints { make in make.height.equalTo(18) }
        switch style {
        case .dark: label.textColor = .white
        case .light: label.textColor = .black
        case .accent: label.textColor = .white
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 9
        switch style {
        case .dark: layer?.backgroundColor = AppColor.badgeDarkFill.cgColor
        case .light: layer?.backgroundColor = AppColor.badgeLightFill.cgColor
        case .accent: layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}
