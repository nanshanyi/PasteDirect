//
//  PasteShortcutsSettingViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Cocoa
import Preferences
import KeyboardShortcuts

class PasteShortcutsSettingViewController: NSViewController, SettingsPane {
    let preferencePaneIdentifier = Settings.PaneIdentifier.shortcuts
    let preferencePaneTitle = "快捷键"
    override var nibName: NSNib.Name? { "PasteShortcutsSettingViewController" }
    

    @IBOutlet weak var pasteCell: NSGridCell!
    @IBOutlet weak var shortcutsView: NSView!
    var toolbarItemIcon: NSImage {
        NSImage(systemSymbolName: "command", accessibilityDescription: nil)!
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .pasteKey)
        recorder.frame = NSRect(x: 0, y: 0, width: 100, height: 30)
        pasteCell.contentView?.addSubview(recorder)
    }
    
}
