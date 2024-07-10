//
//  PasteCollectionViewItem.swift
//  PasteDirect
//
//  Created by 南山忆 on 2024/7/10.
//

import AppKit
import Carbon
import KeyboardShortcuts
import SnapKit
import UIColorHexSwift

protocol PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indePath: IndexPath)
}

let maxLength = 500

class PasteCollectionViewItem: NSCollectionViewItem {
    public var delegate: PasteCollectionViewItemDelegate?
    private var pModel: PasteboardModel!
    private var keyMonitor: Any?

    private lazy var gradenLayer = CAGradientLayer().then {
        $0.startPoint = CGPoint(x: 0, y: 1)
        $0.endPoint = CGPoint(x: 0, y: 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        initSubviews()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.enterKeyDown(with: event)
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 4 : 0
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        gradenLayer.frame = bottomView.bounds
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.type == .leftMouseDown, event.clickCount == 2 {
            pasteText(true)
        }
    }

    private lazy var topView = NSView().then {
        $0.wantsLayer = true
        $0.addSubview(typeLabel)
        $0.addSubview(timeLabel)
        $0.addSubview(iconImageView)
        typeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.spacing)
            make.bottom.equalTo(timeLabel.snp.top).offset(-4)
        }

        timeLabel.snp.makeConstraints { make in
            make.leading.equalTo(typeLabel)
            make.bottom.equalToSuperview().offset(-12)
        }

        iconImageView.snp.makeConstraints { make in
            make.top.bottom.trailing.equalToSuperview()
            make.width.equalTo(70)
        }
    }

    private lazy var iconImageView = NSImageView().then {
        $0.alignment = .center
        $0.imageScaling = .scaleAxesIndependently
    }

    private lazy var typeLabel = NSTextField().then {
        $0.isEditable = false
        $0.isSelectable = false
        $0.isBordered = false
        $0.textColor = .white
        $0.maximumNumberOfLines = 1
        $0.backgroundColor = .clear
        $0.font = .systemFont(ofSize: 18, weight: .medium)
    }

    private lazy var timeLabel = NSTextField().then {
        $0.isEditable = false
        $0.isSelectable = false
        $0.isBordered = false
        $0.textColor = .white
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .systemFont(ofSize: 12)
    }

    private lazy var contentLabel = NSTextField().then {
        $0.isEditable = false
        $0.isSelectable = false
        $0.isBordered = false
        $0.textColor = .white
        $0.backgroundColor = .clear
        $0.font = .systemFont(ofSize: 14)
        $0.lineBreakMode = .byCharWrapping
        $0.maximumNumberOfLines = 15
    }

    private lazy var contentImageView = NSImageView().then {
        $0.alignment = .center
    }

    private lazy var contentView = PasteEffectImageView().then {
        $0.addSubview(contentImageView)
        contentImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.spacing)
            make.trailing.equalToSuperview().offset(-Layout.spacing)
            make.top.equalToSuperview().offset(Layout.spacing)
            make.bottom.equalToSuperview().offset(-24)
        }
    }

    private lazy var bottomView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.addSublayer(gradenLayer)
        $0.addSubview(bottomLabel)
        bottomLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }
    }

    private lazy var bottomLabel = NSTextField().then {
        $0.isEditable = false
        $0.isSelectable = false
        $0.isBordered = false
        $0.alignment = .center
        $0.textColor = .systemGray
        $0.backgroundColor = .clear
        $0.maximumNumberOfLines = 1
        $0.font = .systemFont(ofSize: 12)
    }
}

extension PasteCollectionViewItem {
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderColor = NSColor("#3970ff")?.cgColor
        view.addSubview(topView)
        view.addSubview(contentView)
        view.addSubview(contentLabel)
        view.addSubview(bottomView)
        topView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(70)
        }

        contentView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(topView.snp.bottom)
        }

        contentLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Layout.spacing)
            make.trailing.equalToSuperview().offset(-Layout.spacing)
            make.top.equalTo(topView.snp.bottom).offset(Layout.spacing)
            make.bottom.equalToSuperview().offset(-24)
        }

        bottomView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(24)
        }
    }
}

extension PasteCollectionViewItem {
    public func updateItem(model: PasteboardModel) {
        pModel = model
        switch pModel.type {
        case .image:
            setImageItem()
        case .string:
            setStringItem()
        default:
            break
        }
        if !pModel.appPath.isEmpty {
            iconImageView.imageScaling = .scaleAxesIndependently
            let iconImage = NSWorkspace.shared.icon(forFile: pModel.appPath)
            iconImageView.image = iconImage
            Task {
                let color = await PasteDataStore.main.colorWith(pModel).cgColor
                topView.layer?.backgroundColor = color
            }
        } else {
            topView.layer?.backgroundColor = NSColor(red: 41.0 / 255.0, green: 42.0 / 255.0, blue: 48.0 / 255.0, alpha: 1).cgColor
        }
        setViewMenu()
        timeLabel.stringValue = model.date.timeAgo
    }

    private func setStringItem() {
        contentView.isHidden = true
        contentLabel.isHidden = false
        if let att = pModel.attributeString {
            var showStr = att

            if att.length > maxLength {
                showStr = att.attributedSubstring(from: NSMakeRange(0, maxLength))
            }

            if att.length > 0,
               let color = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor,
               let colorstr = color.usingColorSpace(.deviceRGB)?.hexString(false)
            {
                contentLabel.attributedStringValue = showStr
                view.layer?.backgroundColor = color.cgColor
                let startColor = NSColor("\(colorstr)00") ?? NSColor(white: 0, alpha: 0)
                let endColor = NSColor("\(colorstr)cc") ?? NSColor(white: 0, alpha: 1)
                gradenLayer.colors = [startColor.cgColor, endColor.cgColor]

            } else {
                view.layer?.backgroundColor = NSColor.white.cgColor
                contentLabel.stringValue = showStr.string
                contentLabel.textColor = .black
                gradenLayer.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0.8).cgColor]
            }
            bottomLabel.stringValue = "\(att.string.count)个字符"
        }

        typeLabel.stringValue = "文本"
    }

    private func setImageItem() {
        contentView.isHidden = false
        contentLabel.isHidden = true
        let retImage = NSImage(data: pModel.data)
        contentView.image = retImage
        contentImageView.image = retImage
        typeLabel.stringValue = "图片"
        view.layer?.backgroundColor = NSColor.white.cgColor
        gradenLayer.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
        if let size = retImage?.size {
            bottomLabel.stringValue = "\(Int(size.width)) ×\(Int(size.height)) 像素"
        }
    }

    private func setViewMenu() {
        let menu = NSMenu()
        if let app = NSApplication.shared.delegate as? PasteAppDelegate, let name = app.frontApp?.localizedName {
            let item = NSMenuItem(title: "粘贴到\(name)", action: #selector(menuAttributeText), keyEquivalent: "")
            menu.addItem(item)
        }
        if !PasteUserDefaults.pasteOnlyText {
            let item1 = NSMenuItem(title: "粘贴为纯文本", action: #selector(pasteText), keyEquivalent: "")
            menu.addItem(item1)
        }
        let item2 = NSMenuItem(title: "复制", action: #selector(copyItemData), keyEquivalent: "")
        menu.addItem(item2)
        let item3 = NSMenuItem(title: "删除", action: #selector(deleteItem), keyEquivalent: "d")
        item3.keyEquivalentModifierMask = .init(rawValue: 0)
        menu.addItem(item3)
        view.menu = menu
    }
}

// MARK: - 事件处理

extension PasteCollectionViewItem {
    private func enterKeyDown(with event: NSEvent) -> NSEvent? {
        if isSelected, event.type == .keyDown, event.keyCode == kVK_Return {
            pasteText(true)
            return nil
        }
        return event
    }

    @objc private func pasteText(_ isAttribute: Bool = false) {
        let direct = PasteUserDefaults.pasteDirect
        let attri = isAttribute && !PasteUserDefaults.pasteOnlyText
        PasteBoard.main.pasteData(pModel, attri)
        guard direct else { return }
        if let app = NSApplication.shared.delegate as? PasteAppDelegate {
            app.frontApp?.activate()
            app.dismissWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                    KeyboardShortcuts.postCmdVEvent()
                }
            }
        }
    }

    @objc func menuAttributeText() {
        pasteText(true)
    }

    @objc func copyItemData() {
        if let app = NSApplication.shared.delegate as? PasteAppDelegate {
            app.dismissWindow()
            PasteBoard.main.pasteData(pModel)
            app.frontApp?.activate()
        }
    }

    @objc func deleteItem() {
        if let indexPath = collectionView?.indexPath(for: self) {
            delegate?.deleteItem(pModel, indePath: indexPath)
        }
    }
}

extension PasteCollectionViewItem: UserInterfaceItemIdentifier {}
