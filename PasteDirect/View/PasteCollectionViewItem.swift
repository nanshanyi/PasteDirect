//
//  PasteCollectionViewItem.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Carbon
import Cocoa
import KeyboardShortcuts
import UIColorHexSwift

protocol PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indePath: IndexPath)
}

class PasteCollectionViewItem: NSCollectionViewItem {
    @IBOutlet var contentLabel: NSTextField!

    @IBOutlet var contentImage: NSImageView!

    @IBOutlet var appImageView: NSImageView!

    @IBOutlet var itemType: NSTextField!

    @IBOutlet var itemTime: NSTextField!

    @IBOutlet var topContentView: NSView!

    @IBOutlet var bottomView: NSView!

    @IBOutlet var bottomLabel: NSTextField!

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
        if event.type == .leftMouseDown
            && event.clickCount == 2 {
            pasteText(true)
        }
    }
    
    private func initSubviews() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderColor = NSColor("#3970ff")?.cgColor
        topContentView.wantsLayer = true
        bottomView.wantsLayer = true
        bottomView.layer?.addSublayer(gradenLayer)
        contentLabel.lineBreakMode = .byCharWrapping
        contentLabel.maximumNumberOfLines = 15
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
            appImageView.imageScaling = .scaleAxesIndependently
            let iconImage = NSWorkspace.shared.icon(forFile: pModel.appPath)
            appImageView.image = iconImage
            topContentView.layer?.backgroundColor = mainDataStore.colorWith(pModel).cgColor
        } else {
            topContentView.layer?.backgroundColor = NSColor(red: 41.0 / 255.0, green: 42.0 / 255.0, blue: 48.0 / 255.0, alpha: 1).cgColor
        }
        setViewMenu()
        itemTime.stringValue = getTimeString(model.date)
    }

    private func setStringItem() {
        contentImage.isHidden = true
        contentLabel.isHidden = false
        if let att = pModel.attributeString {
            var showStr = att
            
            if att.length > 500 {
                showStr = att.attributedSubstring(from: NSMakeRange(0, 500))
            }
            
            if att.length > 0,
                let color = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor,
               let colorstr = color.usingColorSpace(.deviceRGB)?.hexString(false) {
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

        itemType.stringValue = "文本"
    }

    private func setImageItem() {
        contentImage.isHidden = false
        contentLabel.isHidden = true
        let retImage = NSImage(data: pModel.data)
        contentImage.image = retImage
        itemType.stringValue = "图片"
        gradenLayer.colors = [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 1).cgColor]
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
        if !UserDefaults.standard.bool(forKey: PrefKey.pasteOnlyText.rawValue) {
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

    private func getTimeString(_ date: Date) -> String {
        let diffDate = NSCalendar.current.dateComponents([.month, .day, .hour, .minute], from: date, to: Date())
        if let month = diffDate.month, month > 0 {
            return "\(month)月前"
        } else if let day = diffDate.day, day > 0 {
            return "\(day)天前"
        } else if let hour = diffDate.hour, hour > 0 {
            return "\(hour)小时前"
        } else if let minute = diffDate.minute, minute > 0 {
            return "\(minute)分钟前"
        } else {
            return "刚刚"
        }
    }

}

// MARK: - 事件处理

extension PasteCollectionViewItem {
    
    private func enterKeyDown(with event: NSEvent) -> NSEvent? {
        if isSelected && event.type == .keyDown && event.keyCode == kVK_Return {
            pasteText(true)
            return nil
        }
        return event
    }
    
    @objc func pasteText(_ isAttribute: Bool = false) {
        let direct = UserDefaults.standard.bool(forKey: PrefKey.pasteDirect.rawValue)
        let attri = isAttribute && !UserDefaults.standard.bool(forKey: PrefKey.pasteOnlyText.rawValue)
        PasteBoard.main.pasteData(pModel, attri)
        if !direct { return }
        if let app = NSApplication.shared.delegate as? PasteAppDelegate {
            app.frontApp?.activate()
            app.dismissWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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

extension PasteCollectionViewItem: UserInterfaceItemIdentifier {
    static var identifier: NSUserInterfaceItemIdentifier = .init(rawValue: "PasteCollectionViewItem")
}
