//
//  PasteCollectionViewItem.swift
//  Paste
//
//  Created by 南山忆 on 2022/10/21.
//

import Cocoa
import UIColorHexSwift
import Carbon
import KeyboardShortcuts

protocol PasteCollectionViewItemDelegate {
    func deleteItem(_ item: PasteboardModel, indePath: IndexPath)
}

class PasteCollectionViewItem: NSCollectionViewItem{
    
    @IBOutlet weak var contentLabel: NSTextField!
    @IBOutlet weak var contentImage: NSImageView!
    
    @IBOutlet weak var appImageView: NSImageView!
    
    @IBOutlet weak var itemType: NSTextField!
    
    @IBOutlet weak var itemTime: NSTextField!
    
    @IBOutlet weak var topContentView: NSView!
    
    @IBOutlet weak var bottomView: NSView!
    
    @IBOutlet weak var bottomLabel: NSTextField!
    
    var gradenLayer: CAGradientLayer  = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 1)
        layer.endPoint = CGPoint(x: 0, y: 0)
        return layer
    }()
    var delegate: PasteCollectionViewItemDelegate?
    var pModel: PasteboardModel!
    private var keyMonitor: Any?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderColor = NSColor("#3970ff")?.cgColor
        topContentView.wantsLayer = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            return self.enterKeyDown(with: event)
        }
        bottomView.wantsLayer = true;
        bottomView.layer?.addSublayer(gradenLayer)
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.maximumNumberOfLines = 15
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
    
    func updateItem(model: PasteboardModel ) {
        pModel = model
        
        if pModel.type == .string {
            contentImage.isHidden = true
            contentLabel.isHidden = false
            
            topContentView.layer?.backgroundColor = NSColor(red: 41.0/255.0, green: 42.0/255.0, blue: 48.0/255.0, alpha: 1).cgColor
            if let att = pModel.attributeString {
                var showStr = att
                if att.string.count > 500 {
                    showStr = att.attributedSubstring(from: NSMakeRange(0, 500))
                }
                contentLabel.attributedStringValue = showStr
                
                if att.length > 0, let color = att.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor {
                    view.layer?.backgroundColor = color.cgColor
                    //                    contentLabel.layer?.backgroundColor = color.cgColor
                    let colorstr = color.hexString(false)
                    let startColor = NSColor("\(colorstr)00") ?? NSColor(white: 0, alpha: 0)
                    let endColor = NSColor("\(colorstr)cc") ?? NSColor(white: 0, alpha: 1)
                    gradenLayer.colors = [startColor.cgColor, endColor.cgColor]
                    
                } else {
                    view.layer?.backgroundColor = NSColor.white.cgColor
                    contentLabel.textColor = .black
                    gradenLayer.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor.white.cgColor]
                }
                bottomLabel.stringValue = "\(att.string.count)个字符"
            }
            
            itemType.stringValue = "文本"
        } else if pModel.type == .image {
            contentImage.isHidden = false
            contentLabel.isHidden = true
            let retImage = NSImage(data: model.data)
            contentImage.image = retImage
            itemType.stringValue = "图片"
            gradenLayer.colors = [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 1).cgColor]
            if let size = retImage?.size {
                bottomLabel.stringValue = "\(Int(size.width)) ×\(Int(size.height)) 像素"
            }
        }
        if pModel.appPath.count > 0 {
            appImageView.imageScaling = .scaleAxesIndependently
            let iconImage = NSWorkspace.shared.icon(forFile: model.appPath)
            appImageView.image = iconImage
            self.topContentView.layer?.backgroundColor = mainDataStore.colorWith(model).cgColor
        }
        setViewMenu()
        itemTime.stringValue = getTimeString(model.date)
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.type == .leftMouseDown {
            if event.clickCount == 2 {
                pasteText(true)
            }
        }
    }
    
    func setViewMenu() {
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
    
    func getTimeString(_ date:Date) -> String {
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

    func enterKeyDown(with event: NSEvent) -> NSEvent? {
        if isSelected && event.type == .keyDown && event.keyCode == kVK_Return {
            pasteText(true)
            return nil
        }
        return event
    }
}

extension PasteCollectionViewItem {
    
    @objc func pasteText(_ isAttribute:Bool = false) {
        let direct = UserDefaults.standard.bool(forKey: PrefKey.pasteDirect.rawValue)
        let attri = isAttribute && !UserDefaults.standard.bool(forKey: PrefKey.pasteOnlyText.rawValue)
        PasteBoard.main.setData(pModel,attri)
        if !direct {
            return
        }
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
            PasteBoard.main.setData(pModel)
            app.frontApp?.activate()
        }
    }
    @objc func deleteItem() {
        if let indexPath = collectionView?.indexPath(for: self) {
            delegate?.deleteItem(pModel, indePath: indexPath)
        }
        
    }
}
