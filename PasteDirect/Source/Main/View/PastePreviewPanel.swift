//
//  PastePreviewPanel.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/09.
//

import AppKit
import Carbon
import SnapKit

// MARK: - PastePreviewPopover

final class PastePreviewPopover: NSPopover {

    private let previewVC = PastePreviewViewController()

    static let maxWidth: CGFloat = Layout.previewMaxSize
    static let maxHeight: CGFloat = Layout.previewMaxHeight
    static let miniHeight: CGFloat = Layout.previewMinHeight
    static let minWidth: CGFloat = Layout.previewMinWidth
    init(model: PasteboardModel) {
        super.init()
        behavior = .transient
        animates = true
        contentViewController = previewVC
        _ = previewVC.view
        configure(with: model)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with model: PasteboardModel) {
        let size = Self.fitSize(for: model)
        previewVC.configure(with: model, contentSize: size)
        contentSize = NSSize(width: size.width + Layout.previewPadding, height: size.height + Layout.previewInfoPadding)
    }


    @MainActor
    private static func fitSize(for model: PasteboardModel) -> NSSize {
        switch model.type {
        case .image:
            guard let image = NSImage(data: model.data) else {
                return NSSize(width: maxWidth, height: maxHeight)
            }
            let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
            let w = image.size.width / screenScale
            let h = image.size.height / screenScale
            return NSSize(width: min(w, Layout.previewMaxSize), height: min(h, Layout.previewMaxSize))
        case .string:
            return textFitSize(for: model)
        default:
            return NSSize(width: Layout.previewMinWidth, height: Layout.previewMinWidth)
        }
    }

    @MainActor
    private static func textFitSize(for model: PasteboardModel) -> NSSize {
        let font = NSFont.systemFont(ofSize: 13)
        let maxLayoutWidth = maxWidth - Layout.previewPadding
        var boundingSize = NSSize(width: maxWidth, height: maxHeight)
        if let attributeString = model.attributeString {
            boundingSize = attributeString.boundingRect(
                with: NSSize(width: maxLayoutWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        } else {
            boundingSize = (model.dataString as NSString).boundingRect(
                with: NSSize(width: maxLayoutWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).size
        }
        let w = min(max(ceil(boundingSize.width + Layout.previewPadding), minWidth), maxWidth)
        let h = min(max(boundingSize.height, miniHeight), maxHeight)
        return NSSize(width: w, height: h)
    }
}

// MARK: - PastePreviewViewController

final class PastePreviewViewController: NSViewController {

    // MARK: - 文本

    private lazy var scrollView = NSScrollView().then {
        $0.hasVerticalScroller = true
        $0.hasHorizontalScroller = false
        $0.autohidesScrollers = true
        $0.drawsBackground = false
        $0.borderType = .noBorder
    }

    private lazy var textView: NSTextView = {
        let tv = NSTextView()
        tv.font = .systemFont(ofSize: 13)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: Layout.previewTextInset, height: Layout.previewTextInset)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        return tv
    }()

    // MARK: - 图片

    private lazy var imageView = NSImageView().then {
        $0.imageAlignment = .alignCenter
    }

    // MARK: - 颜色

    private lazy var colorContentView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.cornerRadius = Layout.previewCornerRadius
        $0.layer?.masksToBounds = true
    }

    private lazy var hexLabel = NSlabel().then {
        $0.alignment = .center
        $0.font = .systemFont(ofSize: 28, weight: .medium)
        $0.backgroundColor = .clear
    }

    // MARK: - 底部信息

    private lazy var typeLabel = NSlabel().then {
        $0.textColor = .labelColor
        $0.font = .systemFont(ofSize: 18, weight: .medium)
        $0.alignment = .left
        $0.maximumNumberOfLines = 1
        $0.backgroundColor = .clear
        $0.setContentHuggingPriority(.required, for: .horizontal)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private lazy var infoLabel = NSlabel().then {
        $0.textColor = .secondaryLabelColor
        $0.font = .systemFont(ofSize: 12)
        $0.alignment = .left
        $0.maximumNumberOfLines = 1
        $0.backgroundColor = .clear
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0,
                                      width: PastePreviewPopover.maxWidth,
                                      height: PastePreviewPopover.maxHeight))
        view.wantsLayer = true

        scrollView.documentView = textView

        view.addSubview(scrollView)
        view.addSubview(imageView)
        view.addSubview(colorContentView)
        view.addSubview(typeLabel)
        view.addSubview(infoLabel)

        colorContentView.addSubview(hexLabel)

        // 文本 scrollView：填满内容区上方
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(typeLabel.snp.top).offset(-8)
        }

        // 图片：居中，宽高在 showImage 中更新
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-Layout.previewCornerRadius)
            make.width.equalTo(0)
            make.height.equalTo(0)
        }

        // 颜色区域：填满上方
        colorContentView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.equalToSuperview().offset(4)
            make.trailing.equalToSuperview().offset(-4)
            make.bottom.equalTo(typeLabel.snp.top).offset(-8)
        }

        hexLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(Layout.previewCornerRadius)
        }

        // 底部信息栏
        typeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.previewTextInset)
            make.bottom.equalToSuperview().offset(-8)
        }

        infoLabel.snp.makeConstraints { make in
            make.leading.equalTo(typeLabel.snp.trailing).offset(4)
            make.trailing.equalToSuperview().offset(-Layout.previewTextInset)
            make.centerY.equalTo(typeLabel)
        }

        hideAll()
    }

    func configure(with model: PasteboardModel, contentSize: NSSize) {
        hideAll()
        typeLabel.stringValue = model.type.string
        switch model.type {
        case .string:
            showText(model)
        case .image:
            showImage(model, size: contentSize)
        case .color:
            showColor(model)
             
        default:
            break
        }

        typeLabel.isHidden = false
        infoLabel.isHidden = false
    }

    private func hideAll() {
        scrollView.isHidden = true
        imageView.isHidden = true
        colorContentView.isHidden = true
        typeLabel.isHidden = true
        infoLabel.isHidden = true
    }

    // MARK: - 文本

    private func showText(_ model: PasteboardModel) {
        scrollView.isHidden = false

        // 背景色跟 item 一致
        let fullAtt = NSAttributedString(with: model.data, type: model.pasteboardType)
        let att = fullAtt ?? model.attributeString
        if let att, att.length > 0,
           let bgColor = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor {
            textView.textStorage?.setAttributedString(att)
            textView.backgroundColor = bgColor
            textView.drawsBackground = true
        } else {
            textView.drawsBackground = false
            textView.textColor = .textColor
            textView.string = model.dataString
        }

        var infoParts: [String] = []
        if !model.appName.isEmpty { infoParts.append(model.appName) }
        infoParts.append(model.date.timeAgo)
        let charCount = model.dataString.count
        infoParts.append("\(charCount)\(String(localized: "characters"))")
        infoLabel.stringValue = infoParts.joined(separator: "  ·  ")
    }

    // MARK: - 图片

    private func showImage(_ model: PasteboardModel, size: NSSize) {
        imageView.isHidden = false
        guard let image = NSImage(data: model.data) else { return }
        imageView.image = image

        let imgW = size.width
        let imgH = size.height
        imageView.snp.updateConstraints { make in
            make.width.equalTo(imgW)
            make.height.equalTo(imgH)
        }

        var infoParts: [String] = []
        if !model.appName.isEmpty { infoParts.append(model.appName) }
        infoParts.append("\(Int(image.size.width)) × \(Int(image.size.height))")
        infoLabel.stringValue = infoParts.joined(separator: "  ·  ")
    }

    // MARK: - 颜色

    private func showColor(_ model: PasteboardModel) {
        colorContentView.isHidden = false
        guard let hex = model.hexColorString, let color = NSColor(hex) else { return }

        colorContentView.layer?.backgroundColor = color.cgColor

        let textColor = HexColorValidator.textColor(for: color)
        hexLabel.textColor = textColor
        hexLabel.stringValue = hex

        // 底部信息：RGB · HSL · HSB
        var infoParts: [String] = []
        if let rgb = color.usingColorSpace(.deviceRGB) {
            let r = Int(rgb.redComponent * 255)
            let g = Int(rgb.greenComponent * 255)
            let b = Int(rgb.blueComponent * 255)
            infoParts.append("RGB \(r), \(g), \(b)")

            let h = Int(rgb.hueComponent * 360)
            let s = Int(rgb.saturationComponent * 100)
            let l = Int((2 - rgb.saturationComponent) * rgb.brightnessComponent / 2 * 100)
            infoParts.append("HSL \(h), \(s), \(l)")

            let hb = Int(rgb.brightnessComponent * 100)
            infoParts.append("HSB \(h), \(s), \(hb)")
        }
        infoLabel.stringValue = infoParts.joined(separator: "  ·  ")
    }
}
