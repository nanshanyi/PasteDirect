//
//  PastePreviewPanel.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/09.
//

import AppKit
import Carbon
import ImageIO
import SnapKit
import VisionKit

// MARK: - PastePreviewPopover

final class PastePreviewPopover: NSPopover {

    private let previewVC = PastePreviewViewController()

    static let miniHeight: CGFloat = Layout.previewMinHeight
    static let minWidth: CGFloat = Layout.previewMinWidth

    /// 预览最大宽度。取设计上限与屏幕可见宽度的较小值，保证面板不超出屏幕。
    @MainActor
    static var maxWidth: CGFloat {
        let usable = (NSScreen.main?.visibleFrame.width ?? Layout.previewMaxWidth) - Layout.previewPadding - Layout.screenPadding * 2
        return min(Layout.previewMaxWidth, max(minWidth, usable))
    }

    /// 预览最大高度。预览贴着主列表面板弹出，纵向要与之共享屏幕，
    /// 故从可见高度里再扣掉主面板高度，避免大图预览在小屏上被挤压或溢出。
    @MainActor
    static var maxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? Layout.previewMaxHeight
        let usable = screenHeight - Layout.viewHeight - Layout.previewInfoPadding - Layout.screenPadding * 2
        return min(Layout.previewMaxHeight, max(miniHeight, usable))
    }
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
        previewVC.configure(with: model)
        contentSize = NSSize(width: size.width + Layout.previewPadding, height: size.height + Layout.previewInfoPadding)
    }


    @MainActor
    private static func fitSize(for model: PasteboardModel) -> NSSize {
        switch model.type {
        case .image:
            // 按真实比例显示(像系统预览)，imageView 用此尺寸即贴合图片
            let display = imageDisplaySize(for: model)
            return NSSize(width: display.width, height: display.height)
        case .string:
            return textFitSize(for: model)
        default:
            return NSSize(width: minWidth, height: miniHeight)
        }
    }

    /// 图片的真实等比显示尺寸(点)。保持宽高比，最大不超过 max 框，小图不放大。
    @MainActor
    fileprivate static func imageDisplaySize(for model: PasteboardModel) -> NSSize {
        // 优先用记录的原图像素尺寸算比例，避免解码(原图已外置，列表持有的是缩略图)
        let pixelSize: CGSize
        if let w = model.imageWidth, let h = model.imageHeight, w > 0, h > 0 {
            pixelSize = CGSize(width: w, height: h)
        } else if let image = NSImage(data: model.data) {
            pixelSize = image.size
        } else {
            return NSSize(width: maxWidth, height: maxHeight)
        }
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        let naturalW = pixelSize.width / screenScale
        let naturalH = pixelSize.height / screenScale
        // 等比缩到 max 框内，ratio 上限取 1 表示小图不放大
        let ratio = min(maxWidth / naturalW, maxHeight / naturalH, 1)
        return NSSize(width: naturalW * ratio, height: naturalH * ratio)
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
        // 等比缩放，永不拉伸(像系统预览)
        $0.imageScaling = .scaleProportionallyUpOrDown
        // 圆角裁切，与颜色预览块一致
        $0.wantsLayer = true
        $0.layer?.cornerRadius = Layout.previewCornerRadius
        $0.layer?.masksToBounds = true
    }

    // 系统实况文本(Live Text)叠加层，让图片里的文字可直接选中/复制
    private lazy var imageAnalysisOverlay = ImageAnalysisOverlayView().then {
        $0.trackingImageView = imageView
        $0.preferredInteractionTypes = .automatic
    }

    private let imageAnalyzer = ImageAnalyzer()
    // 防止异步分析结果回写到已被复用于其它条目的 overlay
    private var imageAnalysisToken = UUID()

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
        imageView.addSubview(imageAnalysisOverlay)
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

        // Live Text 叠加层贴合图片显示区域
        imageAnalysisOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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

    func configure(with model: PasteboardModel) {
        hideAll()
        typeLabel.stringValue = model.type.string
        switch model.type {
        case .string:
            showText(model)
        case .image:
            showImage(model)
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
        imageAnalysisOverlay.analysis = nil
        imageAnalysisOverlay.isHidden = true
        imageAnalysisToken = UUID()
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

    private func showImage(_ model: PasteboardModel) {
        imageView.isHidden = false
        imageAnalysisOverlay.isHidden = false

        // imageView 用图片真实等比尺寸，圆角恰好裁在图片边缘
        let display = PastePreviewPopover.imageDisplaySize(for: model)
        imageView.snp.updateConstraints { make in
            make.width.equalTo(display.width)
            make.height.equalTo(display.height)
        }

        // 先用列表已持有的缩略图即时显示，再异步加载原图替换为清晰大图
        if let thumb = NSImage(data: model.data) {
            imageView.image = thumb
        }
        let token = imageAnalysisToken
        Task { [weak self] in
            let originalData = await PasteDataStore.main.loadOriginalImageData(for: model)
            // 原图可能有数 MB,解码放后台线程避免主线程掉帧;CGImage 可 Sendable,回主线程包 NSImage
            let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithData(originalData as CFData, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }.value
            guard let self, self.imageAnalysisToken == token, let decoded else { return }
            let image = NSImage(cgImage: decoded, size: .zero)
            self.imageView.image = image
            // 原图就绪后做系统级文字识别，使图片中的文字可被选中/复制
            await self.analyzeImageForLiveText(image, token: token)
        }

        var infoParts: [String] = []
        if !model.appName.isEmpty { infoParts.append(model.appName) }
        if let w = model.imageWidth, let h = model.imageHeight, w > 0, h > 0 {
            infoParts.append("\(w) × \(h)")
        } else if let thumb = imageView.image {
            infoParts.append("\(Int(thumb.size.width)) × \(Int(thumb.size.height))")
        }
        infoLabel.stringValue = infoParts.joined(separator: "  ·  ")
    }

    /// 用系统 VisionKit 对原图做 Live Text 分析，结果叠加到 overlay 上，
    /// 让用户像系统「实况文本」一样直接选中、复制图片中的文字。
    private func analyzeImageForLiveText(_ image: NSImage, token: UUID) async {
        let configuration = ImageAnalyzer.Configuration([.text])
        do {
            let analysis = try await imageAnalyzer.analyze(image, orientation: .up, configuration: configuration)
            guard imageAnalysisToken == token else { return }
            imageAnalysisOverlay.analysis = analysis
        } catch {
            guard imageAnalysisToken == token else { return }
            imageAnalysisOverlay.analysis = nil
        }
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
