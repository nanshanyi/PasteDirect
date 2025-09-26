//
//  PasteShortcutsSettingViewController.swift
//  Paste
//
//  Created by 南山忆 on 2022/11/14.
//

import Cocoa
import KeyboardShortcuts
import SnapKit

final class PasteShortcutsSettingViewController: NSViewController {
    @IBOutlet weak var pasteCell: NSGridCell!
    override var nibName: NSNib.Name? { "PasteShortcutsSettingViewController" }

    override func viewDidLoad() {
        super.viewDidLoad()
        let recorder = KeyboardShortcuts.RecorderCocoa(for: .pasteKey)
        pasteCell.contentView?.addSubview(recorder)
        recorder.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
}
