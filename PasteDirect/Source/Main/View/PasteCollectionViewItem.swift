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
import Foundation

protocol PasteCollectionViewItemDelegate: NSObjectProtocol {
    func deleteItem(_ item: PasteboardModel, indexPath: IndexPath)
}

let maxLength = 300

final class PasteCollectionViewItem: NSCollectionViewItem {
    weak var delegate: PasteCollectionViewItemDelegate?
    private var pModel: PasteboardModel?
    private var keyMonitor: Any?
    private var isAttribute: Bool = true
    private var observation: NSKeyValueObservation?

    private lazy var contentView = NSView().then {
        $0.wantsLayer = true
        $0.layer?.masksToBounds = true
        $0.layer?.backgroundColor = .clear
        $0.layer?.cornerRadius = 16
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
            make.bottom.equalToSuperview().offset(-24)
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
            contentView.layer?.borderWidth = isSelected ? 4 : 0
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.type == .leftMouseDown, event.clickCount == 2 {
            pasteAction()
        }
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
        
        topMask.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
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
            make.width.equalTo(topView.snp.height)
        }
    }

    private func initContentView() {
        view.addSubview(contentView)
        contentView.addSubview(topView)
        contentView.addSubview(imageContentView)
        contentView.addSubview(contentLabel)
        contentView.addSubview(bottomView)

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        topView.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(60)
        }

        imageContentView.snp.makeConstraints { make in
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
        timeLabel.stringValue = model.date.timeAgo
        typeLabel.stringValue = model.type.string
        bottomLabel.stringValue = model.sizeString(or: pasteImageView.image)
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

    private func setViewMenu() {
        
        let menu = NSMenu()
        if let app = NSApplication.shared.delegate as? PasteAppDelegate,
            let name = app.frontApp?.localizedName {
            let item = NSMenuItem(title: "粘贴到\(name)", action: #selector(pasteAttributeTextClick), keyEquivalent: "")
            menu.addItem(item)
        }
        if pModel?.type == .string {
            let item1 = NSMenuItem(title: "粘贴为纯文本", action: #selector(pasteOnlyTextClick), keyEquivalent: "")
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
    private func initObserver() {
        observation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            app.effectiveAppearance.performAsCurrentDrawingAppearance {
                if self?.isAttribute != true {
                    self?.contentView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
                }
            }
        }
    }

    @objc
    private func pasteOnlyTextClick() {
        pasteAction(false)
    }
    
    @objc
    private func pasteAttributeTextClick() {
        pasteAction(true)
    }

    private func pasteAction(_ isAttribute: Bool = true) {
        Log("isAttribute: \(isAttribute) data: \(pModel?.dataString ?? "")")
        PasteBoard.main.pasteData(pModel, isAttribute)
        guard PasteUserDefaults.pasteDirect else { return }
        guard let app = NSApplication.shared.delegate as? PasteAppDelegate else { return }
        app.frontApp?.activate()
        app.dismissWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                KeyboardShortcuts.postCmdVEvent()
            }
        }
    }

    @objc
    private func copyItemData() {
        guard let pModel, let app = NSApplication.shared.delegate as? PasteAppDelegate else { return }
        app.dismissWindow()
        PasteBoard.main.pasteData(pModel)
        app.frontApp?.activate()
    }

    @objc
    private func deleteItem() {
        if let pModel, let indexPath = collectionView?.indexPath(for: self) {
            delegate?.deleteItem(pModel, indexPath: indexPath)
        }
    }
}

extension PasteCollectionViewItem: UserInterfaceItemIdentifier {}

