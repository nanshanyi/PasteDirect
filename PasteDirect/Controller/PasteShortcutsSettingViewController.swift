//
//  PasteShortcutsSettingViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Cocoa
import KeyboardShortcuts
import Preferences

class PasteShortcutsSettingViewController: NSViewController, SettingsPane {
    @IBOutlet var pasteCell: NSGridCell!
    @IBOutlet var shortcutsView: NSView!

    let preferencePaneIdentifier = Settings.PaneIdentifier.shortcuts
    let preferencePaneTitle = "快捷键"
    override var nibName: NSNib.Name? { "PasteShortcutsSettingViewController" }

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
